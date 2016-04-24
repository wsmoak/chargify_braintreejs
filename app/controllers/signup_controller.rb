class SignupController < ApplicationController

  def index
    Braintree::Configuration.environment = :sandbox
    Braintree::Configuration.merchant_id = ENV["BRAINTREE_MERCHANT_ID"]
    Braintree::Configuration.public_key = ENV["BRAINTREE_PUBLIC_KEY"]
    Braintree::Configuration.private_key = ENV["BRAINTREE_PRIVATE_KEY"]

    @token = Braintree::ClientToken.generate
  end

  def create
    first_name = params[:first_name]
    last_name = params[:last_name]
    email = params[:email]

    nonce = params[:payment_method_nonce]

    result = Braintree::Customer.create(
      :first_name => first_name,
      :last_name => last_name,
      :email => email,
      :payment_method_nonce => nonce
    )

    puts "******* BRAINTREE RESULT ********"
    puts result.inspect

    if result.success?
      vault_token = result.customer.id
    else
      raise result.errors
    end

    Chargify.configure do |c|
      c.api_key   = ENV["CHARGIFY_API_KEY"]
      c.subdomain = ENV["CHARGIFY_BRAINTREE_SUBDOMAIN"]
    end

    if result.customer.credit_cards.any?
      subscription = Chargify::Subscription.create(
        :product_handle => 'basic',
        :customer_attributes => {
          :first_name => first_name,
          :last_name => last_name,
          :email => email
        },
        :credit_card_attributes => {
          :first_name => first_name,
          :last_name => last_name,
          :vault_token => result.customer.id,
          :card_type => result.customer.credit_cards[0].card_type.downcase,
          :expiration_month => result.customer.credit_cards[0].expiration_month,
          :expiration_year => result.customer.credit_cards[0].expiration_year,
          :last_four => result.customer.credit_cards[0].last_4,
          :current_vault => "braintree_blue"
        }
      )
    elsif result.customer.paypal_accounts.any?
      subscription = Chargify::Subscription.create(
        :product_handle => 'basic',
        :customer_attributes => {
          :first_name => first_name,
          :last_name => last_name,
          :email => email
        },
        :paypal_account_attributes => {
          :first_name => first_name,
          :last_name => last_name,
          :vault_token => result.customer.id,
          :paypal_email => email,
          :payment_method_nonce => "required_for_paypal_account_but_not_used_because_we_have_a_vault_token",
          :current_vault => "braintree_blue"
        }
      )
    else
      raise "Subscription not created because Braintree Result did not have a credit card or a PayPal account"
    end

    puts "****** CHARGIFY SUBSCRIPTION ******"
    puts subscription.inspect

    if subscription.errors.any?
      raise subscription.errors.full_messages.join(", ")
    end
  end
end
