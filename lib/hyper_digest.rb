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
      coin = detail["coin"]
      szi = detail["szi"]
      margin_used = detail["marginUsed"].to_f
      position_value = detail["positionValue"].to_f
      unrealized_pnl = detail["unrealizedPnl"].to_f
      leverage_type = detail.dig("leverage", "type")
      leverage_value = detail.dig("leverage", "value")
      liquidation_px = detail["liquidationPx"]

      summary << "\n\t#{coin}: #{szi}"
      summary << "\n\t  Margin Used: #{fmt_usd(margin_used)}"
      summary << "\n\t  Position Value: #{fmt_usd(position_value)}"
      summary << "\n\t  Unrealized PnL: #{fmt_usd(unrealized_pnl)}"
      if leverage_type && leverage_value
        summary << "\n\t  Leverage: #{leverage_type} #{leverage_value}x"
      elsif leverage_value
        summary << "\n\t  Leverage: #{leverage_value}x"
      end
      summary << "\n\t  Liquidation Px: #{liquidation_px.nil? ? "N/A" : fmt_usd(liquidation_px.to_f)}"
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
