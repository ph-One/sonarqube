#
# Sonar, entreprise quality control tool.
# Copyright (C) 2009 SonarSource SA
# mailto:contact AT sonarsource DOT com
#
# Sonar is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 3 of the License, or (at your option) any later version.
#
# Sonar is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with Sonar; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02
#
class DashboardsController < ApplicationController

  SECTION=Navigation::SECTION_RESOURCE

  verify :method => :post, :only => [:create, :update, :delete, :up, :down, :follow, :unfollow], :redirect_to => {:action => :index}
  before_filter :login_required

  def index
    @actives=ActiveDashboard.user_dashboards(current_user)
    @shared_dashboards=Dashboard.find(:all, :conditions => ['(user_id<>? OR user_id IS NULL) AND shared=?', current_user.id, true], :order => 'name ASC')
    active_dashboard_ids=@actives.map{|a| a.dashboard_id}
    @shared_dashboards.reject!{|d| active_dashboard_ids.include?(d.id)}

    @resource=Project.by_key(params[:resource])
    if @resource.nil?
      # TODO display error page
      redirect_to home_path
      return false
    end
    return access_denied unless has_role?(:user, @resource)
    @snapshot = @resource.last_snapshot
    @project=@resource  # variable name used in old widgets
  end

  def create
    @dashboard=Dashboard.new()
    load_dashboard_from_params(@dashboard)
    if @dashboard.valid?
      @dashboard.save

      add_default_dashboards_if_first_user_dashboard
      last_active_dashboard=current_user.active_dashboards.max{|x,y| x.order_index<=>y.order_index}
      current_user.active_dashboards.create(:dashboard => @dashboard, :user_id => current_user.id, :order_index => (last_active_dashboard ? last_active_dashboard.order_index+1: 1))
      redirect_to :controller => 'dashboard', :action => 'configure', :id => @dashboard.id, :resource => params[:resource]
    else
      flash[:error]=@dashboard.errors.full_messages.join('<br/>')
      redirect_to :controller => 'dashboards', :action => 'index', :resource => params[:resource]
    end
  end

  def edit
    @dashboard=Dashboard.find(params[:id])
    if @dashboard.owner?(current_user)
      render :partial => "edit"
    else
      redirect_to :controller => 'dashboards', :action => 'index', :resource => params[:resource]
    end
  end

  def update
    dashboard=Dashboard.find(params[:id])
    if dashboard.owner?(current_user)
      load_dashboard_from_params(dashboard)

      if dashboard.save
        if !dashboard.shared?
          ActiveDashboard.destroy_all(["dashboard_id = ? and (user_id<>? OR user_id IS NULL)", dashboard.id, current_user.id])
        end
      else
        flash[:error]=dashboard.errors.full_messages.join('<br/>')
      end
    else
      # TODO explicit error
    end
    redirect_to :action => 'index', :resource => params[:resource]
  end

  def delete
    dashboard=Dashboard.find(params[:id])
    if current_user.active_dashboards.size<=1
      flash[:error]='At least one dashboard must be defined'
      redirect_to :action => 'index', :resource => params[:resource]

    elsif dashboard.owner?(current_user)
      dashboard.destroy
      flash[:notice]='Dashboard deleted'
      redirect_to :action => 'index', :resource => params[:resource]
    else
      # TODO explicit error
      redirect_to home_path
    end
  end

  def down
    add_default_dashboards_if_first_user_dashboard
    dashboard_index=-1
    current_user.active_dashboards.each_with_index do |ad, index|
      ad.order_index=index+1
      if ad.dashboard_id==params[:id].to_i
        dashboard_index=index
      end
    end
    if dashboard_index>-1 && dashboard_index<current_user.active_dashboards.size-1
      current_user.active_dashboards[dashboard_index].order_index+=1
      current_user.active_dashboards[dashboard_index+1].order_index-=1
    end
    current_user.active_dashboards.each do |ad|
      ad.save
    end
    redirect_to :action => 'index', :resource => params[:resource]
  end

  def up
    add_default_dashboards_if_first_user_dashboard
    dashboard_index=-1
    current_user.active_dashboards.each_with_index do |ad, index|
      ad.order_index=index+1
      dashboard_index=index if ad.dashboard_id==params[:id].to_i
    end
    if dashboard_index>0
      current_user.active_dashboards[dashboard_index].order_index-=1
      current_user.active_dashboards[dashboard_index-1].order_index+=1
    end
    current_user.active_dashboards.each do |ad|
      ad.save
    end
    redirect_to :action => 'index', :resource => params[:resource]
  end

  def follow
    add_default_dashboards_if_first_user_dashboard()
    dashboard=Dashboard.find(:first, :conditions => ['shared=? and id=? and (user_id is null or user_id<>?)', true, params[:id].to_i, current_user.id])
    if dashboard
      active=current_user.active_dashboards.to_a.find{|a| a.dashboard_id==params[:id].to_i}
      if active.nil?
        current_user.active_dashboards.create(:dashboard => dashboard, :user => current_user, :order_index => current_user.active_dashboards.size+1)
      end
    end
    redirect_to :action => :index, :resource => params[:resource]
  end

  def unfollow
    if current_user.active_dashboards.size<=1
      flash[:error]='At least one dashboard must be defined'
    else
      active_dashboard=ActiveDashboard.find(:first, :conditions => ['user_id=? AND dashboard_id=?', current_user.id, params[:id].to_i])
      active_dashboard.destroy if active_dashboard
    end
    redirect_to :action => :index, :resource => params[:resource]
  end

  private

  def load_dashboard_from_params(dashboard)
    dashboard.name=params[:name]
    dashboard.description=params[:description]
    dashboard.shared=(params[:shared].present? && is_admin?)
    dashboard.user_id=current_user.id
    dashboard.column_layout='50-50' if !dashboard.column_layout
  end

  def add_default_dashboards_if_first_user_dashboard
    if current_user.active_dashboards.empty?
      defaults=ActiveDashboard.default_dashboards
      defaults.each do |default_active|
        current_user.active_dashboards.create(:dashboard => default_active.dashboard, :user => current_user, :order_index => current_user.active_dashboards.size+1)
      end
    end
  end



end