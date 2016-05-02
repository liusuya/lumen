module Lumen
  class App < Padrino::Application
    
    use Rack::Timeout, service_timeout: 25
    
    if ENV['FORCE_SSL']
      use Rack::SslEnforcer
      use Rack::Session::Cookie, :key => '_rack_session', :path => '/', :expire_after => 365*24*60*60, :secret => settings.session_secret
    else
      set :sessions, :expire_after => 1.year    
    end

    require 'sass/plugin/rack'
    Sass::Plugin.options[:template_location] = Padrino.root('app', 'assets', 'stylesheets')
    Sass::Plugin.options[:css_location] = Padrino.root('app', 'assets', 'stylesheets')
    use Sass::Plugin::Rack
    
    register Padrino::Rendering
    register Padrino::Helpers
    register WillPaginate::Sinatra
    helpers Activate::DatetimeHelpers
    helpers Activate::ParamHelpers  
    helpers Activate::NavigationHelpers
    
    use Dragonfly::Middleware
    use Airbrake::Rack    
    use OmniAuth::Builder do
      provider :account
      Provider.registered.each { |provider|
        provider provider.omniauth_name, ENV["#{provider.display_name.upcase}_KEY"], ENV["#{provider.display_name.upcase}_SECRET"], {provider_ignores_state: true}
      }
    end  
    OmniAuth.config.on_failure = Proc.new { |env|
      OmniAuth::FailureEndpoint.new(env).redirect_to_failure
    }    
    
    set :public_folder, Padrino.root('app', 'assets')
    set :default_builder, 'ActivateFormBuilder'    
                      
    before do
      redirect "http://#{ENV['DOMAIN']}#{request.path}" if ENV['DOMAIN'] and request.env['HTTP_HOST'] != ENV['DOMAIN']
      Time.zone = (current_account and current_account.time_zone) ? current_account.time_zone : (ENV['DEFAULT_TIME_ZONE'] || 'London')
      I18n.locale = (current_account and current_account.language) ? current_account.language.code : Language.default.code      
      fix_params!
      @_params = params; def params; @_params; end # force controllers to inherit the fixed params
      if params[:token] and account = Account.find_by(secret_token: params[:token])
        session[:account_id] = account.id
      end
      PageView.create(:account => current_account, :path => request.path) if current_account and !request.xhr? and !params[:token]
    end     
     
    error do
      Airbrake.notify(env['sinatra.error'], :session => session)
      erb :error
    end 
               
    not_found do
      erb :not_found
    end
        
    ############
                  
    get '/' do
      if Account.count == 0       
        account = Account.create!(:name => 'Lumen Admin', :password => 'lumen', :password_confirmation => 'lumen', :email => 'admin@example.com', :admin => true)
        SignIn.create(account: account)
        session[:account_id] = account.id
        flash[:notice] = %Q{<strong>Welcome to Lumen!</strong> An admin account has been created. You'll want to change the name, email address and password.}
        redirect '/me/edit'
      end      
      sign_in_required! unless Fragment.find_by(slug: 'public-homepage')
      if current_account
        @o = :updated       
        erb :home
      else
        erb :'public/homepage'
      end
    end
            
    get '/network' do
      sign_in_required!
      erb :network
    end    
                   
    get '/:slug' do      
      if @fragment = Fragment.find_by(slug: params[:slug], page: true)
        sign_in_required! unless @fragment.public?
        erb :page
      else
        pass
      end
    end   
        
    get '/merge_tags' do
      site_admins_only!
      erb :merge_tags
    end
    
    post '/merge_tags' do
      site_admins_only!
      at1 = AccountTag.find(params[:at1])
      if params[:at2]
        at2 = AccountTag.find(params[:at2])
        at1.account_tagships.each { |account_tagship|
          AccountTagship.create account: account_tagship.account, account_tag: at2
        }
      end
      at1.destroy
      redirect '/merge_tags'
    end
    
    get '/opengraph',  :provides => [:html, :json] do    
      sign_in_required!
      @og = Opengraph.fetch(params[:url])
      case content_type   
      when :json   
        @og.to_json
      when :html      
        partial :opengraph, :locals => {:title => @og[:title], :url => @og[:url], :description => @og[:description], :player => @og[:player], :picture => @og[:picture]}
      end    
    end    
                  
  end
end