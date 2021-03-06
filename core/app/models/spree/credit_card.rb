module Spree
  class CreditCard < Spree::PaymentSource
    before_save :set_last_digits

    # As of rails 4.2 string columns always return strings, we can override it on model level.
    attribute :month, Type::Integer.new
    attribute :year,  Type::Integer.new

    attr_reader :number
    attr_accessor :encrypted_data,
                  :verification_value

    with_options if: :require_card_numbers?, on: :create do
      validates :month, :year, numericality: { only_integer: true }
      validates :number, :verification_value, presence: true, unless: :imported
      validates :name, presence: true
    end

    # needed for some of the ActiveMerchant gateways (eg. SagePay)
    alias_attribute :brand, :cc_type

    # ActiveMerchant::Billing::CreditCard added this accessor used by some gateways.
    # More info: https://github.com/spree/spree/issues/6209
    #
    # Returns or sets the track data for the card
    #
    # @return [String]
    attr_accessor :track_data

    CARD_TYPES = {
      visa: /^4[0-9]{12}(?:[0-9]{3})?$/,
      master: /(^5[1-5][0-9]{14}$)|(^6759[0-9]{2}([0-9]{10})$)|(^6759[0-9]{2}([0-9]{12})$)|(^6759[0-9]{2}([0-9]{13})$)/,
      diners_club: /^3(?:0[0-5]|[68][0-9])[0-9]{11}$/,
      american_express: /^3[47][0-9]{13}$/,
      discover: /^6(?:011|5[0-9]{2})[0-9]{12}$/,
      jcb: /^(?:2131|1800|35\d{3})\d{11}$/
    }

    def expiry=(expiry)
      return unless expiry.present?

      self[:month], self[:year] =
      if expiry.match(/\d{2}\s?\/\s?\d{2,4}/) # will match mm/yy and mm / yyyy
        expiry.delete(' ').split('/')
      elsif match = expiry.match(/(\d{2})(\d{2,4})/) # will match mmyy and mmyyyy
        [match[1], match[2]]
      end
      if self[:year]
        self[:year] = "20#{ self[:year] }" if self[:year] / 100 == 0
        self[:year] = self[:year].to_i
      end
      self[:month] = self[:month].to_i if self[:month]
    end

    def number=(num)
      @number = num.gsub(/[^0-9]/, '') rescue nil
    end

    # cc_type is set by jquery.payment, which helpfully provides different
    # types from Active Merchant. Converting them is necessary.
    def cc_type=(type)
      self[:cc_type] = case type
      when 'mastercard', 'maestro' then 'master'
      when 'amex' then 'american_express'
      when 'dinersclub' then 'diners_club'
      when '' then try_type_from_number
      else type
      end
    end

    def set_last_digits
      number.to_s.gsub!(/\s/,'')
      verification_value.to_s.gsub!(/\s/,'')
      self.last_digits ||= number.to_s.length <= 4 ? number : number.to_s.slice(-4..-1)
    end

    def try_type_from_number
      numbers = number.delete(' ') if number
      CARD_TYPES.find{|type, pattern| return type.to_s if numbers =~ pattern}.to_s
    end

    def verification_value?
      verification_value.present?
    end

    # Show the card number, with all but last 4 numbers replace with "X". (XXXX-XXXX-XXXX-4338)
    def display_number
      "XXXX-XXXX-XXXX-#{last_digits}"
    end

    def has_payment_profile?
      gateway_customer_profile_id.present? || gateway_payment_profile_id.present?
    end

    def to_active_merchant
      ActiveMerchant::Billing::CreditCard.new(
        number: number,
        month: month,
        year: year,
        verification_value: verification_value,
        first_name: first_name,
        last_name: last_name,
      )
    end

    private

    def require_card_numbers?
      !self.encrypted_data.present? && !self.has_payment_profile?
    end
  end
end
