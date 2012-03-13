module GoogleReader
  require "net/http"
  require "net/https"
  require "json"
  

  class Api
    ENDPOINTS = {
      :auth   => "/accounts/ClientLogin",
      :token  => "/reader/api/0/token",
      :list   => "/reader/api/0/subscription/list",
      :edit   => "/reader/api/0/subscription/edit"
    }
    attr_reader :auth_tokens

    def initialize(creds={})
      @base_uri = URI.parse("https://www.google.com")

      @http = Net::HTTP.new(@base_uri.host, @base_uri.port)
      @http.use_ssl = true
      @http.verify_mode = OpenSSL::SSL::VERIFY_NONE

      @auth_tokens = {}
      @subscriptions = nil
      @subscriptions_stale = true

      get_auth(creds)
    end

    def update_subscriptions(grouped_feeds={})
      current_subscriptions = grouped_subscriptions
      grouped_feeds.each do |category, feeds|
        new_feeds = []
        feeds.each do |feed|
          new_feeds << "feed/#{feed}" unless current_subscriptions[category] && current_subscriptions[category].include?("feed/#{feed}")
        end
        unless new_feeds.blank?
          data = {
            :s  => new_feeds,
            :a  => "user/-/label/#{category}",
            :ac => "subscribe",
            :T  => @auth_tokens[:token]
          }
          post_to_reader(ENDPOINTS[:edit], data)

          @subscriptions_stale = true
        end
      end

      grouped_subscriptions
    end

    def grouped_subscriptions
      subscriptions = get_subscriptions["subscriptions"]
      subscription_hash = {}
      subscriptions.each do |subscription|
        # ( subscription_hash[:key] ||= [] ) << value
        sub_id = subscription["id"]
        subscription["categories"].each do |category|
          (subscription_hash[category["label"]] ||= []) << sub_id
        end
      end

      subscription_hash
    end

    def get_subscriptions
      query="output=json"

      if @subscriptions_stale
        begin
          response = get_from_reader(ENDPOINTS[:list], query)
          sub_list = JSON.parse response.body

          @subscriptions_stale = false
        rescue
          sub_list = @subscriptions
        end
      else
        sub_list = @subscriptions
      end


      raise GoogleReader::SubscriptionListError, "subscription list error" if sub_list.nil?

      sub_list
    end

    def get_auth(creds={})
      auth_hash = {
        :accountType => "GOOGLE",
        :service => "reader",
        :source => "bn-reader"
      }.merge(creds)

      response = post_to_reader(ENDPOINTS[:auth], auth_hash, false)
      @auth_tokens = response.body.split(/\n/).inject({}){|hash, token| token_name, token_value = token.split("="); hash[token_name.downcase.to_sym] = token_value; hash}

      response = get_from_reader(ENDPOINTS[:token])
      @auth_tokens[:token] = response.body
    end

    private 

    def get_from_reader(path, query=nil, with_auth=true)
      path = "#{path}?#{query}" if query
      request = Net::HTTP::Get.new(path)
      request["Authorization"] = "GoogleLogin auth=#{@auth_tokens[:auth]}" if with_auth
      response = @http.request(request)

      raise GoogleReader::ResponseError, "bad response code: #{response.code}: #{response.body}" unless response.code == "200"

      response
    end

    def post_to_reader(path, data={}, with_auth=true)
      request = Net::HTTP::Post.new(path)
      request["Authorization"] = "GoogleLogin auth=#{@auth_tokens[:auth]}" if with_auth
      request.set_form_data(data)
      response = @http.request(request)

      raise GoogleReader::ResponseError, "bad response code: #{response.code}: #{response.body}" unless response.code == "200"

      response
    end
  end

  class ResponseError < StandardError

  end

  class SubscriptionListError < StandardError

  end

end