class Admin::PagesController < AlchemyController
  
  helper :pages
  
  layout 'alchemy'
  
  before_filter :set_translation, :except => [:show]
  before_filter :get_page_from_id, :only => [:show, :unlock, :publish, :configure, :edit, :update, :destroy]
  
  filter_access_to [:show, :unlock, :publish, :configure, :edit, :update, :destroy], :attribute_check => true
  filter_access_to [:index, :link, :layoutpages, :new, :switch_language, :create, :fold, :move, :flush], :attribute_check => false
  
  cache_sweeper :pages_sweeper, :if => Proc.new { |c| Alchemy::Configuration.parameter(:cache_pages) }
  
  def index
    @page_root = Page.find_language_root_for(session[:language_id])
  end
  
  def show
    # fetching page via before filter
    @preview_mode = true
    render :layout => 'pages'
  end
  
  def new
    @parent_id = params[:parent_id]
    @page = Page.new
    render :layout => false
  end
  
  def create
    begin
      parent = Page.find_by_id(params[:page][:parent_id]) || Page.root
      page_layout = PageLayout.get(params[:page][:page_layout])
      params[:page][:language_id] ||= parent.language ? parent.language.id : Language.get_default.id
      params[:page][:language_code] ||= parent.language ? parent.language.code : Language.get_default.code
      params[:page][:layoutpage] = ((page_layout["layoutpage"] == true) rescue false)
      page = Page.create(params[:page])
      if page.valid? && parent
        page.move_to_child_of(parent)
      end
      render_errors_or_redirect(page, admin_pages_path, _("page '%{name}' created.") % {:name => page.name})
    rescue Exception => e
      render :update do |page|
        Alchemy::Notice.show_via_ajax(page, _("Error while creating page: %{error}") % {:error => e}, :error)
      end
      log_error($!)
    end
  end
  
  # Edit the content of the page and all its elements and contents.
  def edit
    # fetching page via before filter
    @layoutpage = !params[:layoutpage].blank? && params[:layoutpage] == 'true'
    if @page.locked? && @page.locker.logged_in? && @page.locker != current_user
      flash[:notice] = _("This page is locked by %{name}") % {:name => (@page.locker.name rescue _('unknown'))}
      redirect_to admin_pages_path
    else
      @page.lock(current_user)
    end
  end
  
  # Set page configuration like page names, meta tags and states.
  def configure
    # fetching page via before filter
    if @page.redirects_to_external?
      render :action => 'configure_external', :layout => false
    else
      render :layout => false
    end
  end
  
  def update
    # fetching page via before filter
    @page.update_attributes(params[:page])
    render_errors_or_redirect(@page, request.referer, _("Page %{name} saved") % {:name => @page.name})
  end
  
  def destroy
    # fetching page via before filter
    name = @page.name
    if @page.destroy
      @root_page = Page.find_language_root_for(session[:language_id])
      if @root_page
        render :update do |page|
          page.replace_html(
            "sitemap",
            :partial => 'page',
            :object => @root_page
          )
          Alchemy::Notice.show_via_ajax(page, _("Page %{name} deleted") % {:name => name})
        end
      else
        render :update do |page|
          page.redirect_to admin_pages_url
        end
      end
    end
  end
  
  def link
    @url_prefix = ""
    if configuration(:show_real_root)
      @page_root = Page.root
    else
      @page_root = Page.find_language_root_for(session[:language_id])
    end
    @area_name = params[:area_name]
    @content_id = params[:content_id]
    if params[:link_urls_for] == "newsletter"
      # TODO: links in newsletters has to go through statistic controller. therfore we have to put a string inside the content_rtfs and replace this string with recipient.id before sending the newsletter.
      #@url_prefix = "#{current_server}/recipients/reacts"
      @url_prefix = current_server
    end
    if multi_language?
      @url_prefix = "#{session[:language_id]}/"
    end
    render :layout => false
  end
  
  def fold
    # @page is fetched via before filter
    @page.fold(current_user.id, !@page.folded?(current_user.id))
    @page.save
    render :nothing => true
  end
  
  def layoutpages
    @layout_root = Page.layout_root
  end
  
  # Leaves the page editing mode and unlocks the page for other users
  def unlock
    # fetching page via before filter
    @page.unlock
    flash[:notice] = _("unlocked_page_%{name}") % {:name => @page.name}
    if params[:redirect_to].blank?
      redirect_to admin_pages_path
    else
      redirect_to(params[:redirect_to])
    end
  end
  
  # Sweeps the page cache
  def publish
    # fetching page via before filter
    @page.save
    flash[:notice] = _("page_published") % {:name => @page.name}
    redirect_back_or_to_default(admin_pages_path)
  end
  
  def copy_language
    set_language_to(params[:languages][:new_lang_id])
    begin
      # copy language root from old to new language
      original_language_root = Page.find_language_root_for(params[:languages][:old_lang_id])
      new_language_root = Page.copy(
        original_language_root,
        :language_id => params[:languages][:new_lang_id],
        :language_code => Alchemy::Controller.current_language.code,
        :public => false
      )
      new_language_root.move_to_child_of Page.root
      copy_child_pages(original_language_root, new_language_root)
      flash[:notice] = _('language_pages_copied')
    rescue
      log_error($!)
      flash[:error] = _('language_pages_could_not_be_copied')
    end
    redirect_to :action => :index
  end
  
  def move
    @page_root = Page.find_language_root_for(session[:language_id])
    params['sitemap'].keys.each do |page_id|
      @page = Page.find(page_id)
      if !params['sitemap'][page_id]['left_id'].blank?
        left = Page.find(params['sitemap'][page_id]['left_id'])
        @page.move_to_right_of(left)
      elsif !params['sitemap'][page_id]['parent_id'].blank?
        if params['sitemap'][page_id]['parent_id'] == 'null'
          new_parent = @page_root
        else
          new_parent = Page.find(params['sitemap'][page_id]['parent_id'])
        end
        @page.move_to_child_of(new_parent)
      end
    end
    render :update do |page|
      Alchemy::Notice.show_via_ajax(page, _("Page %{name} moved") % {:name => @page.name})
      page.replace 'sitemap', :partial => 'sitemap'
    end
  end
  
  def switch_language
    set_language_to(params[:language_id])
    if request.xhr?
      render :update do |page|
        page.redirect_to admin_pages_path
      end
    else
      redirect_to admin_pages_path
    end
  end
  
  def flush
    Page.flushables(session[:language_id]).each do |page|
      if multi_language?
        expire_action("#{page.language_code}/#{page.urlname}")
      else
        expire_action("#{page.urlname}")
      end
    end
    render :update do |page|
      Alchemy::Notice.show_via_ajax(page, _('Page cache flushed'))
    end
  end
  
private
  
  def copy_child_pages(source_page, new_page)
    source_page.children.each do |child_page|
      new_child = Page.copy(child_page, :language_id => new_page.language_id, :language_code => new_page.language_code, :public => false)
      new_child.move_to_child_of new_page
      unless child_page.children.blank?
        copy_child_pages(child_page, new_child)
      end
    end
  end
  
  def get_page_from_id
    @page = Page.find(params[:id])
  end
  
end
