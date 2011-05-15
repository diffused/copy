require 'sinatra/base'
require 'erb'
require 'redcarpet'

module Copy 
  class Server < Sinatra::Base    
    set :views,  './views'
    set :public, './public'
    set :root, File.dirname(File.expand_path(__FILE__))
    
    helpers do
      def protected!
        unless authorized?
          response['WWW-Authenticate'] = %(Basic realm="Copy Admin Area")
          throw(:halt, [401, "Not authorized\n"])
        end
      end

      def authorized?
        return false unless settings.respond_to?(:admin_user) && settings.respond_to?(:admin_password)
        @auth ||=  Rack::Auth::Basic::Request.new(request.env)
        @auth.provided? && @auth.basic? && @auth.credentials && @auth.credentials == [settings.admin_user, settings.admin_password]
      end
      
      def set_cache_control_header
        if settings.respond_to?(:cache_time) && settings.cache_time.is_a?(Numeric) && settings.cache_time > 0
          expires settings.cache_time, :public
        else
          cache_control :no_cache
        end
      end
      
      def copy(name, options = {}, &block)
        if !Copy::Storage.connected? || !(content = Copy::Storage.get(name))
          # Side-step the output buffer so we can capture the block, but not output it.
          @_out_buf, old_buffer = '', @_out_buf
          content = yield
          @_out_buf = old_buffer
          
          # Get the first line from captured text.
          first_line = content.split("\n").first
          # Determine how much white space it has in front.
          white_space = first_line.match(/^(\s)*/)[0]
          # Remove that same amount of white space from the beginning of every line.
          content.gsub!(Regexp.new("^#{white_space}"), '')
          
          # Save the content so it can be edited.
          Copy::Storage.set(name, content) if Copy::Storage.connected?
        end
        
        original = content.dup
        # Apply markdown formatting.
        content = Redcarpet.new(content, :smart).to_html.chomp
        
        html_attrs = %Q(class="_copy_editable" data-name="#{name}")
        
        if original =~ /\n/ # content with newlines renders in a div
          tag = options[:wrap_tag] || :div
          output = %Q(<#{tag} #{html_attrs}>#{content}</#{tag}>)
        else # single line content renders in a span without <p> tags
          tag = options[:wrap_tag] || :span
          content.gsub!(/<\/*p>/, '')
          output = %Q(<#{tag} #{html_attrs}>#{content}</#{tag}>)
        end
        
        # Append the output buffer.
        @_out_buf << output
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
    
    get '/_copy/?' do
      protected!
      ERB.new(File.read(File.join(settings.root, 'admin', 'index.html.erb'))).result(self.send(:binding))
    end
    
    get '/_copy/:name' do
      protected!
      @doc = Copy::Storage.get(params[:name])
      ERB.new(File.read(File.join(settings.root, 'admin', 'edit.html.erb'))).result(self.send(:binding))
    end
    
    put '/_copy/:name' do
      protected!
      Copy::Storage.set(params[:name], params[:content])
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