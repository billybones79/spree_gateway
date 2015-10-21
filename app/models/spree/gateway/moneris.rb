module Spree
  class Gateway::Moneris < Gateway
    preference :login, :string
    preference :password, :password

    def provider_class
      ActiveMerchant::Billing::MonerisGateway
    end

    def cancel(response_code, source, options = {})
      response = provider.void(response_code, options)

      unless response.success?
        payment.send(:gateway_error, response)
      end
    end

    def void(response_code, source, options = {})
      response = provider.void(response_code, options)
    end

    def authorize(money, source, options = {})
      if source.gateway_customer_profile_id.nil?
        provider.authorize(money, source, options )
      else
        provider.authorize(money, source.gateway_customer_profile_id, options )
      end
    end

    def credit(credit_cents, source, transaction_id, options = {})
      provider.credit(credit_cents, transaction_id, options )

    end

    def payment_profiles_supported?
      true
    end

    #Customer profile

    def create_profile(payment)
      if payment.source.gateway_customer_profile_id.nil?
        response = provider.store(payment.source)
        payment.source.update_attributes(gateway_customer_profile_id: response.params['data_key'], gateway_payment_profile_id: response.params['data_key'])
      end
    end

  end
end
