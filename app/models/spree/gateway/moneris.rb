module Spree
  class Gateway::Moneris < Gateway
    preference :login, :string
    preference :password, :password

    def provider_class
      ActiveMerchant::Billing::MonerisGateway
    end

    def cancel(response_code)
      provider.void(response_code, {})
    end
    
  end
end
