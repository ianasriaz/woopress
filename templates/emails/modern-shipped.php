<?php
if ( ! defined( 'ABSPATH' ) ) {
    exit;
}

$tracking_number = $order->get_meta('_tracking_number');
$tracking_courier = $order->get_meta('_tracking_courier');
$logo_url = get_option('woopress_email_logo');

?>
<!DOCTYPE html>
<html>
<head>
    <meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
    <title><?php echo esc_html( $email_heading ); ?></title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; background-color: #f4f4f4; margin: 0; padding: 0; -webkit-font-smoothing: antialiased; }
        .container { max-width: 600px; margin: 40px auto; background: #ffffff; border-radius: 8px; overflow: hidden; box-shadow: 0 4px 15px rgba(0,0,0,0.05); }
        .header { text-align: center; padding: 40px 20px 30px; border-bottom: 1px solid #eeeeee; }
        .header img { max-height: 50px; width: auto; margin-bottom: 20px; }
        .header h1 { margin: 0; font-size: 24px; color: #333333; font-weight: 500; }
        .content { padding: 40px; color: #555555; line-height: 1.6; font-size: 15px; }
        .content h2 { font-size: 18px; color: #333333; margin-top: 0; margin-bottom: 15px; font-weight: 500; }
        
        /* Tracking Box Styles */
        .tracking-box { background-color: #f9fafb; border-radius: 8px; padding: 25px; margin: 30px 0; border: 1px solid #e5e7eb; text-align: center; }
        .tracking-box h3 { margin-top: 0; color: #111827; font-size: 16px; margin-bottom: 15px; font-weight: 600; text-transform: uppercase; letter-spacing: 0.5px; }
        .tracking-grid { display: table; width: 100%; margin-bottom: 20px; }
        .tracking-row { display: table-row; }
        .tracking-label { display: table-cell; text-align: right; padding: 5px 15px 5px 0; color: #6b7280; font-size: 14px; width: 50%; }
        .tracking-value { display: table-cell; text-align: left; padding: 5px 0 5px 15px; color: #111827; font-weight: 600; font-size: 15px; width: 50%; word-break: break-all; }
        
        .order-summary { width: 100%; border-collapse: collapse; margin-top: 10px; }
        .order-summary th, .order-summary td { padding: 15px 0; border-bottom: 1px solid #eeeeee; text-align: left; }
        .order-summary th { color: #888888; font-weight: normal; font-size: 14px; }
        .order-summary .total { font-weight: 600; color: #333333; font-size: 18px; }
        .button { display: inline-block; background-color: #000000; color: #ffffff; padding: 14px 28px; text-decoration: none; border-radius: 6px; font-weight: 600; text-align: center; }
        .footer { text-align: center; padding: 30px 20px; font-size: 13px; color: #aaaaaa; }
        
        @media (prefers-color-scheme: dark) {
            body { background-color: #121212 !important; }
            .container { background-color: #1e1e1e !important; box-shadow: 0 4px 15px rgba(0,0,0,0.5) !important; }
            .header { border-bottom: 1px solid #333333 !important; }
            .header h1 { color: #ffffff !important; }
            .content { color: #dddddd !important; }
            .content h2 { color: #ffffff !important; }
            .tracking-box { background-color: #2a2a2a !important; border: 1px solid #333333 !important; }
            .tracking-box h3 { color: #ffffff !important; }
            .tracking-label { color: #9ca3af !important; }
            .tracking-value { color: #ffffff !important; }
            .order-summary th, .order-summary td { border-bottom: 1px solid #333333 !important; }
            .order-summary .total { color: #ffffff !important; }
            .button { background-color: #ffffff !important; color: #000000 !important; }
            .footer { color: #777777 !important; }
        }
        
        @media only screen and (max-width: 600px) {
            .container { margin: 0; border-radius: 0; }
            .content { padding: 30px 20px; }
            .header h1 { font-size: 20px !important; line-height: 1.3 !important; word-wrap: break-word !important; }
            .content h2 { font-size: 16px !important; line-height: 1.4 !important; word-wrap: break-word !important; }
            .tracking-label { text-align: left; display: block; padding: 5px 0 0 0; width: 100%; box-sizing: border-box; }
            .tracking-value { text-align: left; display: block; padding: 0 0 10px 0; width: 100%; word-break: break-all; box-sizing: border-box; }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <?php if ($logo_url) : ?>
                <img src="<?php echo esc_url($logo_url); ?>" alt="<?php echo esc_attr(get_bloginfo('name')); ?>" />
            <?php else : ?>
                <h2 style="margin: 0; font-size: 20px; color: #888888; font-weight: normal; margin-bottom: 15px;"><?php echo esc_html( get_bloginfo('name') ); ?></h2>
            <?php endif; ?>
            <h1><?php echo esc_html( $email_heading ); ?></h1>
        </div>
        <div class="content">
            <p>Hi <?php echo esc_html( $order->get_billing_first_name() ); ?>,</p>
            <p>Great news! Your order has been shipped and is now on its way to you.</p>
            
            <?php if ( ! empty( $tracking_number ) ) : ?>
            <div class="tracking-box">
                <h3>Tracking Details</h3>
                <div class="tracking-grid">
                    <?php if ( ! empty( $tracking_courier ) ) : ?>
                    <div class="tracking-row">
                        <div class="tracking-label">Courier</div>
                        <div class="tracking-value"><?php echo esc_html( $tracking_courier ); ?></div>
                    </div>
                    <?php endif; ?>
                    <div class="tracking-row">
                        <div class="tracking-label">Tracking Number</div>
                        <div class="tracking-value"><?php echo esc_html( $tracking_number ); ?></div>
                    </div>
                </div>
                
                <?php 
                $tracking_url = '#';
                $c = strtolower($tracking_courier);
                if (strpos($c, 'tcs') !== false) $tracking_url = 'https://www.tcsexpress.com/track/';
                elseif (strpos($c, 'leopard') !== false) $tracking_url = 'https://pk.leopardscourier.com/';
                elseif (strpos($c, 'fastex') !== false) $tracking_url = 'https://fastex.pk/trackingDetail/?trackingNo=' . $tracking_number;
                elseif (strpos($c, 'postex') !== false) $tracking_url = 'https://postex.pk/tracking';
                elseif (strpos($c, 'm&p') !== false || strpos($c, 'mp') !== false || strpos($c, 'm and p') !== false) $tracking_url = 'https://mulphilog.com/track-shipment/?tracking_number=' . $tracking_number;
                elseif (strpos($c, 'fedex') !== false) $tracking_url = 'https://www.fedex.com/fedextrack/?trknbr=' . $tracking_number;
                elseif (strpos($c, 'ups') !== false) $tracking_url = 'https://www.ups.com/track?tracknum=' . $tracking_number;
                elseif (strpos($c, 'usps') !== false) $tracking_url = 'https://tools.usps.com/go/TrackConfirmAction?tLabels=' . $tracking_number;
                elseif (strpos($c, 'dhl') !== false) $tracking_url = 'https://www.dhl.com/en/express/tracking.html?AWB=' . $tracking_number;
                else $tracking_url = 'https://parcelsapp.com/en/tracking/' . $tracking_number;
                ?>
                <?php if ($tracking_url !== '#') : ?>
                <a href="<?php echo esc_url($tracking_url); ?>" class="button">Track Package</a>
                <?php endif; ?>
            </div>
            <?php endif; ?>

            <h2 style="margin-top: 30px;">Order summary</h2>
            <table class="order-summary">
                <?php foreach ( $order->get_items() as $item_id => $item ) : ?>
                    <tr>
                        <td style="padding-right: 15px;"><?php echo wp_kses_post( $item->get_name() ); ?> &times; <?php echo esc_html( $item->get_quantity() ); ?></td>
                        <td style="text-align: right; white-space: nowrap;"><?php echo wp_kses_post( wc_price($order->get_line_total( $item, true, true )) ); ?></td>
                    </tr>
                <?php endforeach; ?>
                <tr>
                    <td class="total" style="padding-top: 20px;">Total</td>
                    <td class="total" style="text-align: right; padding-top: 20px;"><?php echo wp_kses_post( $order->get_formatted_order_total() ); ?></td>
                </tr>
                <?php 
                $pm = strtolower($order->get_payment_method_title());
                $pm_display = strtoupper($order->get_payment_method_title());
                if (strpos($pm, 'cash') !== false || strpos($pm, 'cod') !== false) $pm_display = 'COD';
                elseif (strpos($pm, 'bank') !== false) $pm_display = 'BANK TRANSFER';
                elseif ($order->is_paid()) $pm_display = 'PAID';
                ?>
                <tr>
                    <td style="padding-top: 15px; color: #888888; border-bottom: none; font-size: 14px;">Payment Method</td>
                    <td style="text-align: right; padding-top: 15px; color: #333333; border-bottom: none; font-weight: 600;"><?php echo esc_html( $pm_display ); ?></td>
                </tr>
            </table>
        </div>
        <div class="footer">
            &copy; <?php echo date('Y'); ?> <?php echo esc_html( get_bloginfo( 'name' ) ); ?>. All rights reserved.
        </div>
    </div>
</body>
</html>
