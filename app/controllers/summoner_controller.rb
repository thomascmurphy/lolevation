class SummonerController < ApplicationController
  def index
  end

  def search
    if params[:summoner_name].present?
      redirect_to summoner_path(summoner_name: params[:summoner_name],
                                champion_id: params[:champion_id],
                                role: params[:role],
                                tier: params[:tier],
                                region: params[:region],
                                game_count: params[:game_count],
                                games_type: params[:games_type])
    else
      flash[:alert] = "Please enter a valid summoner name"
      redirect_to action: "index"
    end
  end

  def show
    @wide_content = false
    begin
      require 'lol/request'
      if params[:summoner_name].present?
        region = params[:region] || 'na'
        game_count = params[:game_count].to_i > 0 ? [params[:game_count].to_i, 50].min : 10
        @summoner_name = ERB::Util.url_encode(params[:summoner_name].downcase.gsub(/\s+/, ""))
        @summoner = Summoner.find_or_initialize_by(summoner_name: @summoner_name, region: region)
        @champion = Champion.find_by(champion_id: params[:champion_id])
        @role = params[:role]
        @games_type = params[:games_type]
        user_game_ids = []
        lol_request = Lol::Request.new(region)
        if @summoner.new_record?
          summoner_data = lol_request.summoner_by_name(@summoner_name)
          @summoner.summoner_id = summoner_data[summoner_data.keys[0]]["id"]
          full_league_data = lol_request.league_by_summoner(@summoner.summoner_id)
          league_data = full_league_data[full_league_data.keys[0]]
          solo_league = league_data[league_data.find_index {|ranking| ranking["queue"] == "TEAM_BUILDER_RANKED_SOLO"}]
          if solo_league.present?
            @summoner.tier = solo_league["tier"]
          end
          @summoner.save()
        end

        champion_id = params[:champion_id]
        lane_role = ChampionMatch.convertRole(params[:role])
        user_query_hash = {}
        user_query_hash[:champion_id] = params[:champion_id] unless params[:champion_id].blank?
        user_query_hash[:lane] = lane_role[:lane] unless lane_role[:lane].blank?
        user_query_hash[:role] = lane_role[:role] unless lane_role[:role].blank?
        if @games_type == "wins"
          user_query_hash[:winner] = true
        elsif @games_type == "losses"
          user_query_hash[:winner] = false
        end

        api_query = {championIds: champion_id,
                     queue: MATCH::QUEUE_IDS.ranked_solo,
                     beginIndex: 0,
                     endIndex: game_count}
        user_games = @summoner.get_champion_matches(api_query).where(user_query_hash)
        @user_stats = ChampionMatch.average_values(user_games.pluck(:id))

        @tier = params[:tier].presence || @summoner.next_tier()
        comparison_query_hash = {}
        comparison_query_hash[:tier] = @tier unless @tier.blank?

        comparison_games = ChampionMatch.where(user_query_hash.merge(comparison_query_hash))

        @average_stats = ChampionMatch.average_values(comparison_games.pluck(:id))
      else
        flash[:alert] = "Please enter a valid summoner name"
        redirect_to action: "index"
      end

    rescue Lol::TooManyRequests
      flash[:alert] = "We've reached our API limit :( , please try again in a few minutes."
      redirect_to action: "index"
    rescue Lol::NotFound
      flash[:alert] = "Couldn't complete the request, make sure your summoner name and region are entered correctly. Could also be Riot's servers."
      redirect_to action: "index"
    rescue Lol::InvalidAPIResponse
      flash[:alert] = "Invalid API Response"
      redirect_to action: "index"
    rescue Exception => e
      raise e
    end
  end


end
