require 'trello'
require 'asana'
require 'optparse'
require 'open-uri'
require 'tempfile'
require 'mime-types'

options = {}
OptionParser.new do |opts|
  opts.on('--trello-developer-key KEY', 'Trello developer key') do |trello_key|
    options[:trello_developer_key] = trello_key
  end

  opts.on('--trello-member-token TOKEN', 'Trello member token') do |trello_token|
    options[:trello_member_token] = trello_token
  end

  opts.on('--asana-access-token TOKEN', 'Asana access token') do |asana_token|
    options[:asana_access_token] = asana_token
  end

  opts.on('--source-trello-board BOARD_ID', 'Source Trello board ID') do |board_id|
    options[:source_board_id] = board_id
  end

  opts.on('--destination-asana-project PROJECT_ID', 'Destination Asana project ID') do |project_id|
    options[:destination_project_id] = project_id
  end
end.parse!

Trello.configure do |config|
  config.developer_public_key = options[:trello_developer_key]
  config.member_token = options[:trello_member_token]
end

asana = Asana::Client.new do |c|
  c.authentication :access_token, options[:asana_access_token]
end

SOURCE_BOARD = options[:source_board_id]
DESTINATION_PROJECT = options[:destination_project_id]

board = Trello::Board.find(SOURCE_BOARD)

puts "Caching board members..."
member_names = board.members.each_with_object({}) do |member, memo|
  memo[member.id] = member.full_name
end

board.lists.each do |list|
  section = asana.tasks.create(projects: DESTINATION_PROJECT, name: "#{list.name}:")
  puts "Created section for list #{list.name}"

  list.cards.each do |card|
    task_params = {
      name: card.name,
      notes: card.desc,
      projects: DESTINATION_PROJECT,
      memberships: [
        {
          section: section.id,
          project: DESTINATION_PROJECT
        }
      ]
    }

    task = asana.tasks.create(task_params)
    puts "Created task for #{card.name}"

    card.comments.each do |comment|
      text = "Imported Trello comment from #{member_names[comment.member_creator_id]}:\n\n#{comment.text}"
      asana.stories.create_on_task(task: task.id, text: text)
    end

    card.attachments.each do |attachment|
      puts "Found attachment: #{attachment.name}"

      begin
        open(attachment.url) do |file|
          Tempfile.open(attachment.name) do |tmp|
            IO.copy_stream(file, tmp)
            tmp.close

            mime_type = MIME::Types.type_for(tmp.path).first || MIME::Types['application/octet-stream'].first

            task.attach(filename: tmp.path, mime: mime.content_type)
          end
        end
      rescue Exception => e
        puts "Unable to upload attachment: #{attachment.attributes} - #{e.message}"
      end
    end

    card.checklists.each do |checklist|
      puts "Found checklist: #{checklist.name}"
      checklist.check_items.each do |item|
        subtask_params = {
          name: "(#{checklist.name}) #{item['name']}",
          parent: task.id,
          completed: item['state'] == 'complete'
        }

        asana.tasks.create(subtask_params)
        puts "Created subtask #{item['name']} in state #{item['state']}"
      end
    end
  end
end
