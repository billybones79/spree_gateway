require 'spec_helper'

describe Spree::Gateway::Moneris do
  before do
    Spree::Gateway.update_all(active: false)
    @gateway = Spree::Gateway::Moneris.create!(name: 'Moneris Gateway', active: true)
    @gateway.preferences = {
        login: 'store3',
        password: 'yesguy',
        server: 'test',
    }
    @gateway.save!

    with_payment_profiles_off do
      country = create(:country, name: 'United States', iso_name: 'UNITED STATES', iso3: 'USA', iso: 'US', numcode: 840)
      state   = create(:state, name: 'Maryland', abbr: 'MD', country: country)
      address = create(:address,
                       firstname: 'John',
                       lastname:  'Doe',
                       address1:  '1234 My Street',
                       address2:  'Apt 1',
                       city:      'Washington DC',
                       zipcode:   '20123',
                       phone:     '(555)555-5555',
                       state:     state,
                       country:   country
      )

      order = create(:order_with_totals, bill_address: address, ship_address: address)
      order.update!

      @credit_card = create(:credit_card,
                            verification_value: '123',
                            number:             '4242424242424242',
                            month:              9,
                            year:               Time.now.year + 1,
                            name:               'John Doe',
                            cc_type:            'mastercard')

      @payment = create(:payment, source: @credit_card, order: order, payment_method: @gateway, amount: 10.00)
    end
  end

  context '.provider_class' do
    it 'is a Moneris gateway' do
      expect(@gateway.provider_class).to eq ::ActiveMerchant::Billing::MonerisGateway
    end
  end

  context '.payment_profiles_supported?' do
    it 'return true' do
      expect(@gateway.payment_profiles_supported?).to be true
    end
  end

  describe 'authorize' do
    context "the credit card has a token" do
      before(:each) do
        @credit_card.update_attributes(gateway_payment_profile_id: 'test')
      end

      it 'calls provider#authorize using the gateway_payment_profile_id' do
        expect(@gateway.provider).to receive(:authorize).with(500, 'test', {} )
        @gateway.authorize(500, @credit_card)
      end
    end

    context "the given credit card does not have a token" do
      context "the credit card has a payment profile id" do
        before(:each) do
          @credit_card.update_attributes(gateway_payment_profile_id: '12345')
        end

        it 'calls provider#authorize using the gateway_payment_profile_id' do
          expect(@gateway.provider).to receive(:authorize).with(500, '12345', {})
          @gateway.authorize(500, @credit_card)
        end
      end

      context "no payment profile id" do
        it 'calls provider#authorize with the credit card object' do
          expect(@gateway.provider).to receive(:authorize).with(500, @credit_card, {})
          @gateway.authorize(500, @credit_card)
        end
      end
    end

    it 'return a success response with an authorization code' do
      #Avoid duplicate order_id error
      result = @gateway.authorize(500, @credit_card, {order_id: "ord_#{Time.now.to_i}"})
      expect(result.success?).to be true
      expect(result.authorization).to match /^\d{5,}-\d{1}_\d{2};ord_\d+/
    end

    shared_examples 'a valid credit card' do
      it 'work through the spree payment interface' do
        Spree::Config.set auto_capture: false
        expect(@payment.log_entries.size).to eq(0)

        @payment.process!
        expect(@payment.log_entries.size).to eq(1)
        expect(@payment.response_code).to match /^\d{5,}-\d{1}_\d{2};#{@payment.order.number}-#{@payment.number}/
        expect(@payment.state).to eq 'pending'
      end
    end

    context 'when the card is a mastercard' do
      before do
        @credit_card.number = '5555555555554444'
        @credit_card.cc_type = 'mastercard'
        @credit_card.save
      end

      it_behaves_like 'a valid credit card'
    end

    context 'when the card is a visa' do
      before do
        @credit_card.number = '4111111111111111'
        @credit_card.cc_type = 'visa'
        @credit_card.save
      end

      it_behaves_like 'a valid credit card'
    end

    context 'when the card is an amex' do
      before do
        @credit_card.number = '378282246310005'
        @credit_card.verification_value = '1234'
        @credit_card.cc_type = 'amex'
        @credit_card.save
      end

      it_behaves_like 'a valid credit card'
    end
  end

  describe 'capture' do
    it 'do capture a previous authorization' do
      @payment.process!
      expect(@payment.log_entries.size).to eq(1)
      expect(@payment.response_code).to match /^\d{5,}-\d{1}_\d{2};#{@payment.order.number}-#{@payment.number}/

      capture_result = @gateway.capture(@payment.amount, @payment.response_code, {})
      expect(capture_result.success?).to be true
    end

    it 'raise an error if capture fails using spree interface' do
      Spree::Config.set(auto_capture: false)
      expect(@payment.log_entries.size).to eq(0)
      @payment.process!
      expect(@payment.log_entries.size).to eq(1)
      @payment.capture! # as done in PaymentsController#fire
      expect(@payment.completed?).to be true
    end
  end

  context 'purchase' do
    it 'return a success response with an authorization code' do
      result =  @gateway.purchase(500, @credit_card, {order_id: "ord_#{Time.now.to_i}"})
      expect(result.success?).to be true
      expect(result.authorization).to match /^\d{5,}-\d{1}_\d{2};ord_\d+/
    end

    it 'work through the spree payment interface with payment profiles' do
      purchase_using_spree_interface
    end

    it 'work through the spree payment interface without payment profiles' do
      with_payment_profiles_off do
        purchase_using_spree_interface(false)
      end
    end
  end

  context 'void' do
    # Moneris can only void pending payments.
    # If payment was captured, it needs to be credited/refunded
    before do
      Spree::Config.set(auto_capture: false)
    end

    it 'work through the spree credit_card / payment interface' do
      expect(@payment.log_entries.size).to eq(0)
      @payment.process!
      expect(@payment.log_entries.size).to eq(1)
      expect(@payment.response_code).to match /^\d{5,}-\d{1}_\d{2};#{@payment.order.number}-#{@payment.number}/
      @payment.void_transaction!
      expect(@payment.state).to eq 'void'
    end
  end

  def purchase_using_spree_interface(profile=true)
    Spree::Config.set(auto_capture: true)
    @payment.send(:create_payment_profile) if profile
    @payment.log_entries.size == 0
    @payment.process! # as done in PaymentsController#create
    @payment.log_entries.size == 1
    expect(@payment.response_code).to match /^\d{5,}-\d{1}_\d{2};#{@payment.order.number}-#{@payment.number}/
    expect(@payment.state).to eq 'completed'
  end

  def with_payment_profiles_off(&block)
    Spree::Gateway::Moneris.class_eval do
      def payment_profiles_supported?
        false
      end
    end
    yield
  ensure
    Spree::Gateway::Moneris.class_eval do
      def payment_profiles_supported?
        true
      end
    end
  end
end