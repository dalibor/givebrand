#class Float
#  # 0.666666666 -> 66.7
#  def to_percentage
#    100 * (self * (10 ** 3)).round / (10 ** 3).to_f
#  end
#end

require 'redis/sorted_set'

class ScoreCalculator
  attr_accessor :probability, :tolerance, :score_max

  def initialize
    # The bigger the number, less probability
    # we have to teleport to some random link
    @probability = 0.85
    # the smaller the number, the more exact the
    # result will be but more CPU cycles will be needed
    @tolerance = 0.0001
    @score_max = 100
  end

  def calculate
    start = Time.now
    #ActiveRecord::Base.connection.execute('DELETE FROM "user_tag_results"')
    Tag.where("user_tags_count > 0").find_each do |tag|
      total_user_tags = tag.user_tags_count
      # Comment set_scale_range to toggle logaritmic score calculation
      scale_max = probability * total_user_tags + (1 - probability)
      base = scale_max ** 0.01
      scale_range = set_scale_range(scale_max, base)

      rankable_graph = RankableGraph.new
      tag_scores = Redis::SortedSet.new("tag:#{tag.id}:scores")

      tag.user_tags.includes(:votes => {:voter => :user_tags}).order('created_at asc').each do |user_tag|
        tag_scores[user_tag.id] = 0 # initialize scores to 0

        user_tag.votes.each do |vote|
          rankable_graph.link(vote.voteable_id, user_tag.id)
          # findit = vote.voter.user_tags.detect { |vut| vut.tag_id == user_tag.tag_id }
          # if findit
            # rankable_graph.link(findit.id, user_tag.id)
          # end
        end
      end

      rankable_graph.rank(probability, tolerance) do |user_tag_id, rank|
        #user_tag = UserTag.find_by_id user_tag_id rescue nil
        # TODO set outgoing and incoming votes after vote:create so they only get here

        incoming = Redis::Value.new("user_tag:#{user_tag_id}:incoming").value rescue false
        outgoing = Redis::Value.new("user_tag:#{user_tag_id}:outgoing").value rescue false
        if !incoming || !outgoing
          user_tag = UserTag.find_by_id user_tag_id unless user_tag
          user_tag.update_counters
          incoming = Redis::Value.new("user_tag:#{user_tag_id}:incoming").value
          outgoing = Redis::Value.new("user_tag:#{user_tag_id}:outgoing").value
        end

        outgoing = 1 if outgoing.to_i == 0
        weight = rank.to_f * total_user_tags.to_f * (incoming.to_f / (incoming.to_f + outgoing.to_f))

        weight = 1.to_f + weight if weight < 1
        break if weight.infinite?

        if scale_range.present?
          if weight > scale_max
            tag_scores[user_tag_id] = score_max
          else
            scale_range.each_with_index do |range, index|
              if range.cover?(weight)
                tag_scores[user_tag_id] = index
                break
              end
            end
          end
        else
          tag_scores[user_tag_id] = weight
        end
      end

    end

    # List of the last 10 timings (how much time does it take for the calculate_score task to run)
    score_timings = Redis::List.new('calculate_score_timings')
    score_timings.shift if score_timings.size == 10
    score_timings << "#{Time.now - start} sec"
  end

  private
  def set_scale_range(scale_max, base)
    scale_range = []
    (1..score_max).to_a.inject(scale_max) { |result, scale_element|
      scale_range << Range.new(result / base, result)
      result / base
    }
    pom = scale_range.last
    pom = pom.first < pom.last ? pom.first : pom.last
    scale_range << Range.new(0, pom)
    scale_range.reverse
  end
end
