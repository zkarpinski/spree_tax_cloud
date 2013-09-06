require_relative 'tax_cloud/tax_cloud_transaction'

Spree::Order.class_eval do

  has_one :tax_cloud_transaction

  after_save :update_tax_cloud_adjustment

  self.state_machine.after_transition :to => :payment,
     :do => :lookup_tax_cloud,
     :if => :tax_cloud_eligible?

  self.state_machine.after_transition :to => :complete,
     :do => :capture_tax_cloud,
     :if => :tax_cloud_eligible?

  def tax_cloud_eligible?
     ship_address.try(:state_id?)
  end

  def update_tax_cloud_adjustment
    if tax_cloud_eligible?
      if tax_cloud_transaction
        tax_cloud_transaction.update_adjustment(tax_cloud_transaction.adjustment, "Spree::Order")
      else
        lookup_tax_cloud
      end
    end
    return true
  end

  def lookup_tax_cloud
    unless tax_cloud_transaction.nil?
      tax_cloud_transaction.lookup
    else
      create_tax_cloud_transaction
      tax_cloud_transaction.lookup
      tax_cloud_adjustment
    end
  end

  def tax_cloud_adjustment
    adjustments.create do |adjustment|
      adjustment.source = self
      adjustment.originator = tax_cloud_transaction
      adjustment.label = 'Tax'
      adjustment.mandatory = true
      adjustment.eligible = true
      adjustment.amount = tax_cloud_transaction.amount 
    end
  end

  def capture_tax_cloud
    return unless tax_cloud_transaction
    tax_cloud_transaction.capture
  end

   def tax_cloud_total(order)
     line_items_total = order.line_items.sum(&:total)
     cloud_rate = order.tax_cloud_transaction.amount / ( line_items_total + order.ship_total )  
     adjusted_total = line_items_total + order.promotions_total 
     round_to_two_places( adjusted_total * cloud_rate ) 
   end

   def round_to_two_places(amount)
     BigDecimal.new(amount.to_s).round(2, BigDecimal::ROUND_HALF_UP)
   end

   def promotions_total
     promotions = adjustments.eligible.select do |adjustment|
       adjustment.originator_type == "Spree::PromotionAction"  
     end
     promotions.map(&:amount).sum 
   end

   def update_with_taxcloudlookup 
     unless tax_cloud_transaction.nil?
   	  tax_cloud_transaction.lookup 
     end
     update_without_taxcloud_lookup 
   end

  def promotion_shipping
    new_ship_total = ship_total
    ship_promo = 0.0

    adjustments.where("originator_type = ? and label like ? and eligible = ?", "Spree::PromotionAction", "%Free Shipping%", true).all.each do |a|
      ship_promo += a.amount.to_f
    end

    if ship_promo > 0.0

      # Shipping Promotions are a negative number so we add 
      new_ship_total = BigDecimal.new("#{ship_total.to_f + ship_promo.to_f}").round(2, BigDecimal::ROUND_HALF_UP)

      if new_ship_total.to_f < 0.0
        new_ship_total = 0.0
      end
    end

    return  new_ship_total
  end

   # alias_method :update_without_taxcloud_lookup, :update! 
   # alias_method :update!, :update_with_taxcloudlookup 
end
