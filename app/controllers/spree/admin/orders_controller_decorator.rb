Spree::Admin::OrdersController.class_eval do
  after_filter :update_tax, only: [:update]
  
  def update_tax
    logger.info @order.tax_cloud_transaction.inspect

    if @order.tax_cloud_transaction and 
      @order.tax_cloud_eligible? and 
      @order.tax_cloud_transaction.tax_rate > 0.0

      unless @order.tax_cloud_transaction.adjustment
        @order.tax_cloud_adjustment
      end
      
      @order.update_tax_cloud_adjustment
    end
  end
end
