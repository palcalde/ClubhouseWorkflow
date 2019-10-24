require_relative "board_configuration"

class Story
  attr_reader :id, :name, :workflow_state_id, :story_type, :archived, :app_url, :requester_id

  def initialize(opts = {}, board_configuration)

    @id = opts["id"]
    @name = opts["name"]
    @labels = opts["labels"]
    @workflow_state_id = opts["workflow_state_id"]
    @story_type = opts["story_type"]
    @archived = opts["archived"]
    @app_url = opts["app_url"]
    @requester_id = opts["requested_by_id"]

    @board_configuration = board_configuration
  end

  private def labels
    @labels.map { |l| l['name'] }
  end

  def found_in_git()
    found = `git log --grep="#{@id}"`.length > 0
    found
  end

  def belongs_to_team(team_label)
    labels.include? team_label
  end

  def in_version(version)
    labels.include? version
  end

  def is_chore
    story_type == "chore"
  end

  def is_released
    @workflow_state_id == @board_configuration.released_column
  end

  def is_qa_passed
    @workflow_state_id == @board_configuration.qa_passed_column
  end

end

# This is a hash example:

# {
#   "app_url" => "https://app.clubhouse.io/cabify/story/173480", 
#   "description" => "The app is sending clouseau requests always with an empty list:\n\n![](https://cl.ly/1ff66620e6a6/Image%2525202019-10-03%252520at%2525204.57.46%252520PM.png)\n\nMR related: https://gitlab.otters.xyz/product/driver/mobile/product_mobile_android_driver/merge_requests/2195", 
#   "archived" => false, 
#   "started" => true, 
#   "story_links" => [], 
#   "entity_type" => "story", 
#   "labels" => [{
#     "entity_type" => "label",
#     "id" => 50,
#     "created_at" => "2017-03-22T23:49:36Z",
#     "updated_at" => "2017-03-31T08:52:37Z",
#     "name" => "Android",
#     "color" => "#49a940",
#     "external_id" => nil,
#     "archived" => false
#   }, {
#     "entity_type" => "label",
#     "id" => 171950,
#     "created_at" => "2019-09-29T12:11:46Z",
#     "updated_at" => "2019-09-29T12:11:46Z",
#     "name" => "driver-7.8.0",
#     "color" => "#f5e6ad",
#     "external_id" => nil,
#     "archived" => false
#   }], 
#   "mention_ids" => [], 
#   "story_type" => "bug", 
#   "completed_at_override" => nil, 
#   "started_at" => "2019-10-04T08:14:04Z", 
#   "completed_at" => "2019-10-08T08:23:36Z", 
#   "name" => "App is sending clouseau requests empty", 
#   "completed" => true, 
#   "blocker" => false, 
#   "epic_id" => nil, 
#   "requested_by_id" => "5c6abf4f-fe13-451c-b579-f278d5a7ab1b", "iteration_id" => 172317, 
#   "started_at_override" => nil, 
#   "workflow_state_id" => 500000013, 
#   "updated_at" => "2019-10-08T08:23:36Z", 
#   "follower_ids" => ["5c6abf4f-fe13-451c-b579-f278d5a7ab1b"],
#   "owner_ids" => ["5c6abf4f-fe13-451c-b579-f278d5a7ab1b"],
#   "external_id" => nil, 
#   "id" => 173480, 
#   "estimate" => nil, 
#   "position" => 202147467327, 
#   "blocked" => false, 
#   "project_id" => 130778, 
#   "deadline" => nil, 
#   "created_at" => "2019-10-04T08:13:52Z", 
#   "moved_at" => "2019-10-08T08:23:36Z"
# }