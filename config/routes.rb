GetCredible::Application.routes.draw do
  post "tags/search"
  get '/invite' => 'invite#index'

  devise_for :users, :controllers => {
    :sessions => "users/sessions",
    :registrations => "users/registrations",
    :invitations => 'users/invitations'
  }

  resources :users, :only => [:index, :show] do
    member do
      get :followers
      get :following
      get :pending
    end
    resources :user_tags, :only => [:index, :create, :destroy], :path => :tags do
      member do
        post :vote
        post :unvote
      end
    end
  end

  resources :activities, :only => [:show]
  resources :endorsements, :only => [:create, :destroy]

  namespace :twitter do
    resource :session, :only => [:new, :show, :destroy]
    resources :messages, :only => [:create]
    resources :contacts, :only => [:index]
  end

  root :to => 'home#index'

  # static pages
  get '/privacy' => 'home#privacy'
  get '/terms' => 'home#terms'
  get '/tour' => 'home#tour'
  get '/press' => 'home#press'
  get '/team' => 'home#team'

  match '/:id' => 'users#show', :as => 'me_user'
end
