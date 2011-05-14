require 'sinatra/base'

module Copy 
  class Server < Sinatra::Base
    enable :sessions
    
    set :views,  './views'
    set :public, './public'
    
    helpers do
      def set_cache_control_header
        if settings.respond_to?(:cache_time) && settings.cache_time.is_a?(Numeric) && settings.cache_time > 0
          expires settings.cache_time, :public
        else
          cache_control :no_cache
        end
      end
      
      def copy(name, &block)
        if Copy::Storage.connected? && (content = Copy::Storage.get(name))
          # TODO: support haml here
          @_out_buf << content
        else
          # Render the default text in the block
          block.call if block_given?
        end
      end
    end
    
    def self.config(&block)
      class_eval(&block)
    end
    
    before do
      if settings.respond_to?(:storage) && !Copy::Storage.connected?
        Copy::Storage.connect!(settings.storage)
      end
    end
    
    get '/admin/?' do
      "admin"
    end
    
    get '*' do
      route = Copy::Router.new(params[:splat].first, settings.views)
      if route.success?
        set_cache_control_header
        content_type(route.format)
        send(route.renderer, route.template, :layout => route.layout)
      else
        not_found
      end
    end
  end
end