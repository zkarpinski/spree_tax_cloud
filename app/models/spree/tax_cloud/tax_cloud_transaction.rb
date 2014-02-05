# Designed to be the Originator for an Adjustment
# on an order

# require 'exceptional'
require 'spree/tax_cloud'
require 'spree/tax_cloud/tax_cloud_cart_item'
require_dependency 'spree/order'
module Spree
  class TaxCloudTransaction < ActiveRecord::Base
    attr_accessible :tax_rate
    belongs_to :order
    validates :order, :presence => true
    has_one :adjustment, :as => :originator
    has_many :cart_items, :class_name => 'TaxCloudCartItem', :dependent => :destroy

    # called when order updates adjustments
    # This version will tax shipping, which is in cart_price
    def update_adjustment(adjustment, source)
      if adjustment
        create_cart_items

        taxable = ( cart_price + order.promotions_total )
        tax = round_to_two_places( taxable * tax_rate) 

        adjustment.update_attribute_without_callbacks(:amount, tax)
      else
        cart_items.clear
      end
    end

    def lookup
      begin
        create_cart_items
        response = tax_cloud.lookup(self)

        raise 'Tax Cloud Lookup Error' unless response.success?
        transaction do
          logger.info "\n\n *** #{response.inspect}"

          unless response.body[:lookup_response][:lookup_result][:messages].nil?
            self.message = response.body[:lookup_response][:lookup_result][:messages][:response_message][:message]
          end
          
          if response and response.body and response.body[:lookup_response] and 
            response.body[:lookup_response][:lookup_result] and response.body[:lookup_response][:lookup_result][:cart_items_response] and
            response.body[:lookup_response][:lookup_result][:cart_items_response][:cart_item_response]
            
            response_cart_items = Array.wrap(response.body[:lookup_response][:lookup_result][:cart_items_response][:cart_item_response])

            response_cart_items.each do |response_cart_item|
              cart_item = cart_items.find_by_index(response_cart_item[:cart_item_index].to_i)
              cart_item.update_attribute(:amount, response_cart_item[:tax_amount].to_f)
              
              if  (cart_item.price.to_f * cart_item.quantity.to_f) > 0.0
                calculated_rate = "#{response_cart_item[:tax_amount].to_f / (cart_item.price.to_f * cart_item.quantity.to_f)}"
                calculated_rate = BigDecimal.new(calculated_rate).round(3, BigDecimal::ROUND_HALF_UP)
              else
                calculated_rate = 0.0
              end

              unless tax_rate == calculated_rate
                self.tax_rate = calculated_rate
              end
            end

            self.save
          end
        end
      end
    end

    def capture
      tax_cloud.capture(self)
    end

    def amount
      cart_items.map(&:amount).sum
    end

    private
      def cart_price
        total = 0
        cart_items.each do |item|
          total += ( item.price * item.quantity )
        end
        total
      end

      def round_to_two_places(amount)
        BigDecimal.new(amount.to_s).round(2, BigDecimal::ROUND_HALF_UP)
      end

      def tax_cloud
        @tax_cloud = TaxCloud.new
      end

      def create_cart_items
        cart_items.clear
        index = 0
        order.line_items.each do |line_item|
          cart_items.create!({
          :index => (index += 1),
          :tic => Spree::Config.taxcloud_product_tic , 
          :sku => line_item.variant.sku.presence || line_item.variant.id,
          :quantity => line_item.quantity,
          :price => line_item.price.to_f,
          :line_item => line_item
          })
        end

        shiptotal = order.promotion_shipping.to_f

        if shiptotal and shiptotal > 0.0
          cart_items.create!({  
          :index => (index += 1),
          :tic =>  Spree::Config.taxcloud_shipping_tic,  
          :sku => 'SHIPPING',
          :quantity => 1,
          :price =>  shiptotal
          })
        end
      end
  end
end
