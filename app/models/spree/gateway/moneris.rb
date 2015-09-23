module Spree
  class Gateway::Moneris < Gateway
    preference :login, :string
    preference :password, :password

    def provider_class
      ActiveMerchant::Billing::MonerisGateway
    end

    def cancel(response_code)
      p = Spree::Payment.find_by(response_code: response_code)

      puts "###############################################








      p.inspect"


    end
  end
end
