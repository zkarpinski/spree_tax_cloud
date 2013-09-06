class AddRateToAdjustments < ActiveRecord::Migration
  def change
    add_column :spree_tax_cloud_transactions, :tax_rate, :float, default: 0.0
  end
end
