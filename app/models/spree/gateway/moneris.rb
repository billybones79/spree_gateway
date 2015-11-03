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

    def void(response_code, source, options = {})
      provider.void(response_code, options)
    end

    def authorize(money, source, options = {})
      if source.gateway_customer_profile_id.nil?
        provider.authorize(money, source, options )
      else
        provider.authorize(money, source.gateway_customer_profile_id, options )
      end
    end

    def credit(credit_cents, source, transaction_id, options = {})
      provider.refund(credit_cents, transaction_id, options )
    end

    def payment_profiles_supported?
      true
    end

    def disable_customer_profile(source)
      if source.gateway_customer_profile_id
        response = provider.unstore(source.gateway_customer_profile_id)
        if response.success?
          source.update_attributes(gateway_customer_profile_id: nil, gateway_payment_profile_id: nil)
          source.destroy!
        else
          source.send(:gateway_error, response)
        end
      else
        source.destroy!
      end
    end

    #Customer profile

    def create_profile(payment)
      if payment.source.gateway_customer_profile_id.nil?
        response = provider.store(payment.source)
        if response.success?
          payment.source.update_attributes(gateway_customer_profile_id: response.params['data_key'], gateway_payment_profile_id: response.params['data_key'])
        else
          payment.send(:gateway_error, response)
        end
      end
    end

  end
end
