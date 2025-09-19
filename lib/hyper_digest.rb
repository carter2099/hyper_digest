# frozen_string_literal: true

require "hyperliquid"
require "mail"
require_relative "hyper_digest/version"

def fmt_usd(amount)
  "$#{format("%.2f", amount)}"
end

module HyperDigest
  def self.new(wallet_address:, recipient_email:, smtp_address:, smtp_port:, smtp_username:, smtp_password:,
               smtp_domain: "localhost")
    sdk = Hyperliquid.new

    user_state = sdk.info.user_state(wallet_address)
    account_value = user_state["marginSummary"]["accountValue"].to_f.round(2)
    total_margin_used = user_state["marginSummary"]["totalMarginUsed"].to_f.round(2)
    withdrawable = user_state["withdrawable"].to_f.round(2)

    summary = <<~TEXT
      Account Value: #{fmt_usd(account_value)}

      Withdrawable: #{fmt_usd(withdrawable)}

      Total Margin Used: #{fmt_usd(total_margin_used)}

      Positions:
    TEXT

    user_state["assetPositions"].each do |pos|
      detail = pos["position"]
      summary << "\n\t#{detail["coin"]}: #{detail["szi"]}"
    end

    pp user_state
    puts
    puts
    puts

    puts summary

    exit(0)

    smtp_options = {
      address: smtp_address,
      port: smtp_port,
      domain: smtp_domain,
      user_name: smtp_username,
      password: smtp_password,
      authentication: :plain,
      enable_starttls_auto: true
    }

    Mail.defaults { delivery_method :smtp, smtp_options }

    Mail.deliver do
      to recipient_email
      from smtp_username
      subject "test"
      text_part { body "test" }
    end

    puts "Successfully sent HyperDigest to #{recipient_email}"
  end
end
