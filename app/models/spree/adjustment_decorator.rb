Spree::Adjustment.class_eval do
  private
    class << self
      def eligible
        where("eligible = true and amount is not null")
      end
    end
end


