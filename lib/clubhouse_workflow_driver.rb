require "clubhouse_workflow/version"
require "parallel"
require_relative "clubhouse_workflow/story"

module ClubhouseWorkflowDriver
	require 'clubhouse_ruby'

	class ClubhouseDriver

		def initialize(info)
			@info = info
			@clubhouse = ClubhouseRuby::Clubhouse.new(info[:token])

			workflow_list = @clubhouse.workflows.list[:content]
			@workflow = workflow_list.select { |w| w['id'] == info[:workflow_id] }.first

			if !@workflow
				puts "Couldn't access clubhouse workflow, response is #{workflow_list}"
				exit(1)
			end

			@board_configuration = BoardConfiguration.new(
				dev_columns: @workflow['states'].select { |s| info[:dev_columns].include? s['name'] }.map { |c| c['id'] },
				qa_column: @workflow['states'].select { |s| s['name'] == info[:qa_column] }.map { |c| c['id'] }.first,
				qa_passed_column: @workflow['states'].select { |s| s['name'] == info[:qa_passed_column] }.map { |c| c['id'] }.first,
				released_column: @workflow['states'].select { |s| s['name'] == info[:released_column] }.map { |c| c['id'] }.first,
				qa_rejected_label: info[:qa_rejected_label],
				blocked_label: info[:blocked_label]
				)
			@projects = @clubhouse.projects.list[:content].select { |p| info[:projects].include? p['name']}.map { |p| p['id'] }
			@projects_names = @clubhouse.projects.list[:content].select { |p| info[:projects].include? p['name']}.map { |p| { p['id'] => p['name'] }}.reduce({}, :merge)
		end


		private def search_stories(query, max_to_find=100)
			puts "Searching stories with query #{query}"

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

			return stories.map { |s| Story.new(s, @board_configuration) }
		end

		private def stories(updated_since_days=30)			
			@stories ||= @projects.reduce([]) { |acc, id|
				team_label = @info[:team_label]

				updated_since = (Date.today - updated_since_days).strftime

				found_stories = search_stories("project:#{id} updated:#{updated_since}..* label:#{team_label}")

				puts "Found #{found_stories.count} stories for project #{@projects_names[id]}"

				found_in_git_stories = Parallel.map(found_stories) { |s| s.found_in_git() == true ? s : nil }.compact

				acc + found_in_git_stories
			}

			return @stories
		end

		def move_developed_cards(version_name)
			stories
			.select { |s|
				s.in_version(version_name) && s.is_before_qa_backlog && !s.is_blocked && !s.is_released
			}
			.each do |s|
				destination_column = s.is_chore ? @board_configuration.qa_passed_column : @board_configuration.qa_column
				destination_column_name = s.is_chore ? "QA Passed" : "QA Backlog"
				puts "Feature #{s.id} - #{s.name} - found, moving it to #{destination_column_name}"
				move_story(story_id: s.id, to_column: destination_column_name)
				add_comment(story_id: s.id, comment: "Delivered in version #{version_name}")
			end
		end

		def log_stories_for_version(version_name:, comment: nil)
			stories
			.select { |s|
				s.in_version(version_name)
			}
			.each { |s|
				if comment != nil
					puts "Adding comment to #{s.id} #{s.name}"
					add_comment(story_id: s.id, comment: comment)
				end
			}
			.map { |s| 
				msg = "<#{s.app_url}|#{s.name}>"
			}
		end

		def move_released_cards(version_name)
			stories
			.select { |s|
				s.in_version(version_name) && !s.is_released
			}
			.each do |s|
				if !s.is_qa_passed
					requester_mention_name = get_member_mention_name(member_id: s.requester_id)
					comment = "This story has been released without QA approval cc #{requester_mention_name}"
					add_comment(story_id: s.id, comment: comment)
				end
				move_story(story_id: s.id, to_column: @board_configuration.released_column)
				add_comment(story_id: s.id, comment: "Released in version #{version_name}")
			end
		end

		private def move_story(story_id:, to_column:)
			@clubhouse.stories(story_id).update(workflow_state_id: to_column)
		end

		private def add_comment(story_id:, comment:)
			@clubhouse.stories(story_id).comments.create(text: comment)
		end

		private def get_member(member_id:)
			@clubhouse.members.list[:content].select { |member| member['id'] == member_id }.first
		end

		private def get_member_mention_name(member_id:)
			mention_name = get_member(member_id: member_id)['profile']['mention_name']
			"@#{mention_name}"
		end

	end

end