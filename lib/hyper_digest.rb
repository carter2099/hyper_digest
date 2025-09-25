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
    account_value = user_state.dig("marginSummary", "accountValue").to_f.round(2)
    total_margin_used = user_state.dig("marginSummary", "totalMarginUsed").to_f.round(2)
    withdrawable = user_state["withdrawable"].to_f.round(2)

    # Fetch spot balances via SDK
    spot_balances = []
    begin
      spot_resp = sdk.info.spot_balances(wallet_address)
      raw_balances = spot_resp && spot_resp["balances"]
      if raw_balances.is_a?(Array)
        raw_balances.each do |b|
          asset = b["coin"] || b["asset"] || b["name"]
          total = b["total"] || b["balance"] || b["amount"]
          next unless asset && total

          total_f = total.to_f
          next if total_f.zero?

          spot_balances << { asset: asset, amount: total_f }
        end
      end
    rescue StandardError
      spot_balances = []
    end

    # Build HTML digest
    html = []
    html << "<!DOCTYPE html>"
    html << "<html>"
    html << "<head>"
    html << "  <meta charset=\"utf-8\">"
    html << "  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">"
    html << "  <style>body{font-family:-apple-system,BlinkMacSystemFont,Segoe UI,Roboto,Helvetica,Arial,sans-serif;color:#111;margin:0;padding:24px;background:#fafafa} h1{font-size:20px;margin:0 0 16px} h2{font-size:16px;margin:24px 0 8px} table{border-collapse:collapse;width:100%;background:#fff} th,td{border:1px solid #e5e7eb;padding:8px 10px;font-size:13px} th{background:#f3f4f6;text-align:left} .muted{color:#6b7280} .kpi{display:flex;gap:16px;flex-wrap:wrap;margin:8px 0 16px} .kpi div{background:#fff;border:1px solid #e5e7eb;border-radius:6px;padding:10px 12px;min-width:160px} .right{text-align:right}</style>"
    html << "</head>"
    html << "<body>"
    html << "  <h1>HyperDigest — #{wallet_address}</h1>"
    html << "  <div class=\"kpi\">"
    html << "    <div><div class=\"muted\">Account Value</div><div><strong>#{fmt_usd(account_value)}</strong></div></div>"
    html << "    <div><div class=\"muted\">Withdrawable</div><div><strong>#{fmt_usd(withdrawable)}</strong></div></div>"
    html << "    <div><div class=\"muted\">Total Margin Used</div><div><strong>#{fmt_usd(total_margin_used)}</strong></div></div>"
    html << "  </div>"

    # Perp positions table
    positions = Array(user_state["assetPositions"]) || []
    positions = positions.select do |pos|
      detail = pos["position"] || {}
      detail["szi"].to_f != 0.0
    end
    html << "  <h2>Open Perp Positions</h2>"
    if positions.empty?
      html << "  <div class=\"muted\">No open perp positions.</div>"
    else
      html << "  <table>"
      html << "    <thead><tr><th>Asset</th><th>Side</th><th class=\"right\">Size</th><th class=\"right\">Margin Used</th><th class=\"right\">Position Value</th><th class=\"right\">Unrealized PnL</th><th>Leverage</th><th class=\"right\">Liq Px</th></tr></thead>"
      html << "    <tbody>"
      positions.each do |pos|
        detail = pos["position"] || {}
        coin = detail["coin"]
        szi = detail["szi"].to_f
        side = if szi.positive?
                 "Long"
               else
                 (szi.negative? ? "Short" : "Flat")
               end
        display_size = szi.abs
        margin_used = detail["marginUsed"].to_f
        position_value = detail["positionValue"].to_f
        unrealized_pnl = detail["unrealizedPnl"].to_f
        leverage_type = detail.dig("leverage", "type")
        leverage_value = detail.dig("leverage", "value")
        leverage_str = if leverage_value && leverage_type
                         "#{leverage_type} #{leverage_value}x"
                       elsif leverage_value
                         "#{leverage_value}x"
                       else
                         "—"
                       end
        liquidation_px = detail["liquidationPx"]
        html << "      <tr>"
        html << "        <td>#{coin}</td>"
        html << "        <td>#{side}</td>"
        html << "        <td class=\"right\">#{display_size}</td>"
        html << "        <td class=\"right\">#{fmt_usd(margin_used)}</td>"
        html << "        <td class=\"right\">#{fmt_usd(position_value)}</td>"
        html << "        <td class=\"right\">#{fmt_usd(unrealized_pnl)}</td>"
        html << "        <td>#{leverage_str}</td>"
        html << "        <td class=\"right\">#{liquidation_px.nil? ? "N/A" : fmt_usd(liquidation_px.to_f)}</td>"
        html << "      </tr>"
      end
      html << "    </tbody>"
      html << "  </table>"
    end

    # Spot balances table
    html << "  <h2>Spot Balances</h2>"
    if spot_balances.empty?
      html << "  <div class=\"muted\">No spot balances found.</div>"
    else
      html << "  <table>"
      html << "    <thead><tr><th>Asset</th><th class=\"right\">Amount</th></tr></thead>"
      html << "    <tbody>"
      spot_balances.sort_by { |b| -b[:amount].to_f }.each do |b|
        html << "      <tr><td>#{b[:asset]}</td><td class=\"right\">#{b[:amount]}</td></tr>"
      end
      html << "    </tbody>"
      html << "  </table>"
    end

    html << "  <div class=\"muted\" style=\"margin-top:24px\">Generated by HyperDigest</div>"
    html << "</body>"
    html << "</html>"
    html_body = html.join("\n")

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
      subject "HyperDigest — #{wallet_address}"
      html_part do
        content_type "text/html; charset=UTF-8"
        body html_body
      end
    end

    puts "Successfully sent HyperDigest to #{recipient_email}"
  end
end
