require "clubhouse_workflow/version"
require "parallel"

require "clubhouse_workflow_driver" #This is only to make the driver workflow reachable through the gem

module ClubhouseWorkflow
  require 'clubhouse_ruby'

  class Clubhouse
    def initialize(info)
      @info = info
      @clubhouse = ClubhouseRuby::Clubhouse.new(info[:token])

      workflow_list = @clubhouse.workflows.list[:content]
      @workflow = workflow_list.select { |w| w['id'] == info[:workflow_id] }.first

      if !@workflow
        puts "Couldn't access clubhouse workflow, response is #{workflow_list}"
        exit(1)
      end

      @dev_columns = @workflow['states'].select { |s| info[:dev_columns].include? s['name'] }.map { |c| c['id'] }
      @qa_column = @workflow['states'].select { |s| s['name'] == info[:qa_column] }.map { |c| c['id'] }.first
      @qa_passed_column = @workflow['states'].select { |s| s['name'] == info[:qa_passed_column] }.map { |c| c['id'] }.first
      @released_column = @workflow['states'].select { |s| s['name'] == info[:released_column] }.map { |c| c['id'] }.first
      @projects = @clubhouse.projects.list[:content].select { |p| info[:projects].include? p['name']}.map { |p| p['id'] }
      @projects_names = @clubhouse.projects.list[:content].select { |p| info[:projects].include? p['name']}.map { |p| { p['id'] => p['name'] }}.reduce({}, :merge)
    end

    def deliver(build_number)
      stories_in_git.select { |s|
        !is_blocked(s) && !is_released(s)
      }
        .each { |s|
        if s['story_type'] == "chore" && !is_released(s)
          puts "Chore story #{s['id']} found, moving it to Released"
          @clubhouse.stories(s['id']).update(workflow_state_id: @released_column)
          @clubhouse.stories(s['id']).comments.create(text: "Delivered in version #{build_number}")
        elsif is_no_qa_tagged(s) && !is_released(s)
          puts("Feature #{s['id']} found, is No-QA, moving it to Released / Done")
          @clubhouse.stories(s['id']).update(workflow_state_id: @released_column)
          @clubhouse.stories(s['id']).comments.create(text: "No QA story. Delivered in version #{build_number}")
        elsif is_before_qa_backlog(s)
          puts "Feature #{s['id']} found, needs QA, moving it to QA Backlog"
          @clubhouse.stories(s['id']).update(workflow_state_id: @qa_column)
          @clubhouse.stories(s['id']).comments.create(text: "Delivered in version #{build_number}")
        elsif is_qa_passed(s)
          puts("Feature #{s['id']} found, is QA approved, moving it to Released / Done")
          @clubhouse.stories(s['id']).update(workflow_state_id: @released_column)
          @clubhouse.stories(s['id']).comments.create(text: "QA approved. Moving it to Released.")
        end
      }

      get_cards_requiring_qa
    end

    def release(version_number, build_number, completed_days_ago = 0, label = nil)
      deliver(build_number)

      label ||= "rc #{version_number}"

      get_released_cards(completed_days_ago)
        .each { |s|
        add_label(s, "rc #{version_number}")
      }
    end

    def production(version_number, completed_days_ago = 0, label = nil)
      label ||= "🚀 #{version_number}"

      get_released_cards(completed_days_ago)
        .each { |s|
        add_label(s, label)
      }
    end

    def mark_in_progress_cards(version)
      @stories ||= @projects.reduce([]) { |acc, id|
        team_label = @info[:team_label]

        updated_since = (Date.today - updated_since_days).strftime

        found_stories = search("project:#{id} updated:#{updated_since}..* label:#{team_label}")

        puts "found #{found_stories.count} stories for project #{id}"

    end

    def get_released_cards(completed_days_ago = 0)
      stories_in_git
        .select { |s| !already_in_prod(s) && days_since_completed(s) >= completed_days_ago.to_i }
    end

    def get_released_cards_titles()
      get_released_cards
        .map { |s| get_changelog_text_for_story(s) }
    end

    def get_released_cards_titles_for_version(version_number)
      label = "🚀 #{version_number}"
      get_cards_titles_for_label(label)
    end

    def get_release_candidate_cards_titles(version_number)
      label = "rc #{version_number}"
      get_cards_titles_for_label(label)
    end

    private def get_cards_titles_for_label(label)
      stories_in_git
        .select { |s| contains_label(s,label) }
        .group_by { |s| s['project_id'] }
        .map { |k, v|  [ @projects_names[k], v.map { |s| get_changelog_text_for_story(s) } ] }
        .reduce([]){ |acc, item|
        acc + [item[0]] + item[1]
      }
    end

    def get_cards_requiring_qa()
      stories_in_git
        .select { |s| requires_qa(s) }
    end

    def get_cards_requiring_qa_titles()
      get_cards_requiring_qa
        .map { |s| get_changelog_text_for_story(s) }
    end

    def get_slack_changelog_for_stories(stories)
      stories = stories_in_git.map { |s|
        qa_rejected_label = @info[:qa_rejected_label]
        blocked_label = @info[:blocked_label]
        msg = "<#{s['app_url']}|#{s['name']}>"
      }.join(", ")
    end

    def search(query, max_to_find=100)
      puts "searching stories with query #{query}"

      next_id = nil
      stories = []

      loop do
        params = {
          query: query,
          page_size: 25
        }

        if next_id
          params[:next] = next_id
        end

        response = @clubhouse.search_stories(params)

        next_url = response[:content]["next"]
        next_id = next_url ? next_url.match(/next=(.*)/)[1] : nil
        total_found = response[:content]["total"]
        stories += response[:content]["data"]
        stories_left = max_to_find >= total_found

        break if stories.count >= max_to_find || stories.count >= total_found
      end

      return stories
    end

    private def get_column_name(s)
      column_id = s['workflow_state_id']
      column_name =  @workflow['states'].select { |s| s['id'] == column_id }.map { |s| s['name'] }.first
    end

    private def days_since_completed(s)
      completed_at = s['completed_at'] ? DateTime.parse(s['completed_at']) : DateTime.now
      today = DateTime.now
      (today - completed_at).to_i
    end

    private def stories_in_git(allow_search=true, updated_since_days=30)
      if allow_search
        @stories_in_git ||= @projects.reduce([]) { |acc, id|
          team_label = @info[:team_label]

          updated_since = (Date.today - updated_since_days).strftime

          found_stories = search("project:#{id} updated:#{updated_since}..* label:#{team_label}")

          puts "found #{found_stories.count} stories for project #{id}"

          found_in_git_stories = Parallel.map(found_stories) { |s| found_in_git(s) == true ? s : nil }.compact

          acc + found_in_git_stories
        }
      else
        @stories_in_git ||= @projects.reduce([]) { |acc, id|
          acc + @clubhouse.projects(id).stories.list[:content]
            .select { |s| found_in_git(s) && belongs_to_team(s) && !is_archived(s) }
        }
      end

      return @stories_in_git
    end

    # Looks if there is any label containing the rocket emoji.
    # Since we use it to tag releases, it means it was already deployed to prod
    private def already_in_prod(s)
      already_in_prod = !(s["labels"].find { |l| l["name"].include? "🚀" } || []).empty?
      already_in_prod
    end

    private def found_in_git(s)
      found = `git log --grep="#{s['id']}"`.length > 0
      found
    end

    private def get_changelog_text_for_story(s)
      title = "##{s['id']} - #{s['name']} (#{s['app_url']})"
      qa_rejected_label = @info[:qa_rejected_label]
      blocked_label = @info[:blocked_label]
      title = [qa_rejected_label, blocked_label].reduce(title) { |acc, l|
        contains_label(s, l) ? "#{l} " + acc : acc
      }

      return title
    end

    private def is_archived(s)
      s['archived'] == true
    end

    private def add_label(s, l)
      if !contains_label(s, l)
        puts "Adding label #{l} to story #{s['id']}"
        labels = s["labels"].map { |l| { name: l["name"] } }
        labels.push({ name: l })
        @clubhouse.stories(s['id']).update(labels: labels)
      end
    end

    private def contains_label(s, l)
      story_labels = s['labels'].map { |l| l['name'] }
      contains_label = story_labels.include? l

      contains_label
    end

    private def belongs_to_team(s)
      story_labels = s['labels'].map { |l| l['name'] }
      team_label = @info[:team_label]
      belongs_to_team = story_labels.include? team_label

      belongs_to_team
    end

    private def is_blocked(s)
      story_labels = s['labels'].map { |l| l['name'] }
      qa_rejected_label = @info[:qa_rejected_label]
      blocked_label = @info[:blocked_label]
      is_qa_rejected = story_labels.include? qa_rejected_label
      is_blocked = story_labels.include? blocked_label

      is_blocked || is_qa_rejected
    end

    private def is_no_qa_tagged(s)
      story_labels = s['labels'].map { |l| l['name'] }
      no_qa_label = @info[:no_qa_label]

      story_labels.include? no_qa_label
    end

    private def is_before_qa_backlog(s)
      @dev_columns.include? s['workflow_state_id']
    end

    private def requires_qa(s)
      requires_qa_column = @dev_columns + [@qa_column]
      requires_qa_column.include? s['workflow_state_id']
    end

    def is_qa_passed(s)
      @qa_passed_column == s['workflow_state_id']
    end

    def is_released(s)
      @released_column == s['workflow_state_id']
    end

  end
end
