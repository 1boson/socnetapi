require "gdata"

module Socnetapi
  class YoutubeApi
    def initialize params = {}
      raise Socnetapi::Error::NotConnected unless params[:token]

      @youtube = GData::Client::YouTube.new
      @youtube.developer_key = params[:developer_key]
      @youtube.oauth! params[:api_key], params[:api_secret]
      @youtube.authorize_from_access params[:token], params[:secret]
    end

    def profile
      doc = @youtube.get("http://gdata.youtube.com/feeds/api/users/default")
      Nokogiri::XML(doc.body).css("author name").text
    end

    def client
      @youtube
    end

    def friends
      #prepare_friends @youtube.get('http://gdata.youtube.com/feeds/api/users/default/contacts?v=2').body
      response = @youtube.get("http://gdata.youtube.com/feeds/api/users/default/subscriptions?v=2")
      raise Socnetapi::Error::BadResponse unless response.is_a?(GData::HTTP::Response)
      prepare_friends response.body
    rescue exception_block
    end

    def user_entries
      response = @youtube.get("http://gdata.youtube.com/feeds/api/users/default/uploads")
      raise Socnetapi::Error::BadResponse unless response.is_a?(GData::HTTP::Response)
      parse_entries(response.body)
    rescue exception_block
    end

    def delete(id)
      edit_url = "http://gdata.youtube.com/feeds/api/users/default/uploads/#{id}"
      response = @youtube.delete(edit_url)
      raise Socnetapi::Error::BadResponse unless response.is_a?(GData::HTTP::Response)
    rescue exception_block
    end


    def update(id, params = {})
      raise Socnetapi::Error::MissingId unless id
      edit_url = "http://gdata.youtube.com/feeds/api/users/default/uploads/#{id}"

      entry = %{<?xml version="1.0"?>
        <entry xmlns="http://www.w3.org/2005/Atom"
          xmlns:media="http://search.yahoo.com/mrss/"
          xmlns:yt="http://gdata.youtube.com/schemas/2007">
          <media:group>
            <media:title type="plain">#{params[:title]}</media:title>
            <media:description type="plain">#{params[:description]}</media:description>
            <media:category scheme="http://gdata.youtube.com/schemas/2007/categories.cat">People</media:category>
            <media:keywords>#{params[:tags]}</media:keywords>
          </media:group>
        </entry>}

      response = @youtube.put(edit_url, entry)
      raise Socnetapi::Error::BadResponse unless response.is_a?(GData::HTTP::Response)

      @doc = Nokogiri::XML(response.body)
      @doc.at('//yt:videoid').try(:text)
    rescue exception_block
    end


    def create(file_path, params = {})
      feed = 'http://uploads.gdata.youtube.com/feeds/api/users/default/uploads'
      mime_type = ::MIME::Types.type_for(file_path).first.to_s
      entry = %{
      <entry xmlns="http://www.w3.org/2005/Atom"
        xmlns:media="http://search.yahoo.com/mrss/"
        xmlns:yt="http://gdata.youtube.com/schemas/2007">
        <media:group>
          <media:title type="plain">#{params[:title]}</media:title>
          <media:description type="plain">
            #{params[:description]}
          </media:description>
          <media:category
            scheme="http://gdata.youtube.com/schemas/2007/categories.cat">People
          </media:category>
          <media:keywords>#{params[:tags]}</media:keywords>
        </media:group>
      </entry>}
      response = @youtube.post_file(feed, file_path, mime_type, entry)

      raise Socnetapi::Error::BadResponse unless response.is_a?(GData::HTTP::Response)

      @doc = Nokogiri::XML(response.body)
      @doc.at('//yt:videoid').try(:text)
    rescue exception_block
    end

    def get_entries
      response = @youtube.get("http://gdata.youtube.com/feeds/api/users/default/newsubscriptionvideos")
      raise Socnetapi::Error::BadResponse unless response.is_a?(GData::HTTP::Response)
      parse_entries response.body
    rescue exception_block
    end

    def entry id
      response = @youtube.get("http://gdata.youtube.com/feeds/api/videos/#{id}?v=2")
      raise Socnetapi::Error::BadResponse unless response.is_a?(GData::HTTP::Response)
      parse_entry_from_xml response.body
    rescue exception_block
    end

    private

    def parse_entries xml
      @doc = Nokogiri::XML(xml)
      @doc.css('entry').map do |entry|
          parse_entry entry
      end
    end

    def parse_entry_from_xml xml
      @doc = Nokogiri::XML(xml)
      parse_entry @doc.at_css('entry')
    end

    # Entry is a Nokogiri node
    def parse_entry entry
      group_node = entry.css('media|group')
      if id_tag = entry.css('yt|videoid')
        video_id = id_tag.try(:text)
      else
        video_id = parse_entry_id(entry.at_css('id').try(:text))
      end
      {
        id: video_id,
        created_at: entry.at_css('published').try(:text),
        title: entry.at_css('title').try(:text),
        description: entry.at_css('media|description').try(:text),
        tags: entry.at_css('media|keywords').try(:text),
        author: {
          id: entry.at_css('author name').try(:text),
          name: entry.at_css('author name').try(:text),
        },
        thumb: (!entry.css('media|thumbnail').empty?) ? entry.css('media|thumbnail').last['url'] : '',
        url: (!entry.css('media|player').empty?) ? entry.css('media|player').first['url'] : ''
      }
    end

    def prepare_friends friends
      resp = []
      @doc = Nokogiri::XML(friends)
      @doc.css('yt|username').each do |username_node|
        username = username_node.try(:text)
        userdata = JSON.parse(@youtube.get("http://gdata.youtube.com/feeds/api/users/#{username}?fields=yt:username,media:thumbnail&alt=json").body)
        resp << {
         id: username_node.try(:text),
         nickname:  username_node.try(:text),
         name: username_node.try(:text),
         userpic: userdata["entry"]["media$thumbnail"]["url"]
        }
      end
      resp
    end

    def parse_entry_id string
      string.split("/").last
    end

    def exception_block
      (raise ($!.response.respond_to?("status_code") && $!.response.status_code == 401) ? Socnetapi::Error::Unauthorized : $!) if $!
    end
  end
end