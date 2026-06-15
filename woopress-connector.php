<?php
/**
 * Plugin Name: WooPress Connector
 * Description: The Ultimate Standalone Plugin for WooPress SaaS. Installs on any client site to provide 1-click Setup for Stats, Health Radar, and Auto-Notifications via Firebase V1.
 * Version: 2.0.0
 * Author: WooPress
 */

if ( ! defined( 'ABSPATH' ) ) exit;

// ==============================================================================
// 1. VISITOR STATS TRACKING (Replaces functions.php script)
// ==============================================================================

// Inject Cache-Proof Tracking Script
add_action('wp_footer', 'woopress_node_inject_tracker');
function woopress_node_inject_tracker() {
    if (is_admin()) return;
    $today = current_time('Ymd');
    $api_url = esc_url_raw(rest_url('woopress/v1/track'));
    ?>
    <script>
    (function() {
        var today = '<?php echo $today; ?>';
        var storageKey = 'woopress_visitor_tracked_' + today;
        if (!localStorage.getItem(storageKey)) {
            fetch('<?php echo $api_url; ?>', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ action: 'track' })
            }).then(function(response) {
                if (response.ok) {
                    localStorage.setItem(storageKey, '1');
                }
            }).catch(function(e){});
        }
    })();
    </script>
    <?php
}

// Expose REST Endpoints
add_action('rest_api_init', function () {
    // Stats Endpoint (For Flutter App)
    register_rest_route('woopress/v1', '/stats', [
        'methods' => 'GET',
        'callback' => 'woopress_node_get_stats',
        'permission_callback' => '__return_true', // Public read for the Flutter App
    ]);
    
    // Tracking Endpoint (For JS Tracker)
    register_rest_route('woopress/v1', '/track', [
        'methods' => 'POST',
        'callback' => 'woopress_node_record_visit',
        'permission_callback' => '__return_true',
    ]);
});

function woopress_node_record_visit($request) {
    $today = current_time('Ymd');
    $transient_key = 'woopress_daily_visitors_' . $today;
    $count = get_transient($transient_key) ?: 0;
    set_transient($transient_key, $count + 1, DAY_IN_SECONDS);
    return new WP_REST_Response(['status' => 'tracked'], 200);
}

function woopress_node_get_stats() {
    $today = current_time('Ymd');
    $visitors = get_transient('woopress_daily_visitors_' . $today) ?: 0;
    
    $response = new WP_REST_Response([
        'status' => 'success',
        'data' => [
            'date' => current_time('Y-m-d'),
            'visitorsToday' => (int)$visitors
        ]
    ], 200);
    
    // Add 60-second public caching to protect the database during heavy usage
    $response->header('Cache-Control', 'public, max-age=60');
    return $response;
}


// ==============================================================================
// 2. HEALTH RADAR ENDPOINT (For App Diagnostic Checks)
// ==============================================================================

add_action('rest_api_init', function () {
    register_rest_route('woopress/v1', '/health', [
        'methods' => 'GET',
        'callback' => 'woopress_node_get_health',
        'permission_callback' => '__return_true',
    ]);
});

function woopress_node_get_health() {
    return new WP_REST_Response([
        'status' => 'success',
        'message' => 'WooPress Node is Active and Healthy',
        'diagnostics' => [
            'plugin_active' => true,
            'stats_engine' => 'operational',
            'auto_notifications' => 'operational',
            'firebase_credentials_present' => file_exists(plugin_dir_path(__FILE__) . 'wooexpress-firebase-adminsdk-fbsvc-849327c65f.json')
        ]
    ], 200);
}


// ==============================================================================
// 3. AUTO-NOTIFICATIONS (Replaces WooCommerce Webhooks)
// ==============================================================================

// Hook directly into WooCommerce order creation
add_action('woocommerce_new_order', 'woopress_node_trigger_push_new_order', 10, 2);

function woopress_node_trigger_push_new_order($order_id, $order = null) {
    if (!$order_id) return;

    // Fail-proof order fetching
    if (!$order || !is_a($order, 'WC_Order')) {
        $order = wc_get_order($order_id);
    }

    if (!$order) {
        file_put_contents(plugin_dir_path(__FILE__) . 'woopress-node-error.log', date('Y-m-d H:i:s') . " | HOOK ERROR: Could not retrieve WC_Order for ID $order_id\n", FILE_APPEND);
        return;
    }

    // Dynamically generate the topic based on the site's URL
    $raw_url = get_site_url();
    $domain = parse_url($raw_url, PHP_URL_HOST);
    if (!$domain) $domain = str_replace(['http://', 'https://', '/'], '', $raw_url);
    if (strpos($domain, 'www.') === 0) {
        $domain = substr($domain, 4);
    }
    
    $sanitized_domain = str_replace(['.', '-'], '_', $domain);
    $topic = 'orders_' . $sanitized_domain;

    // Extract Order Data
    $customer_name = $order->get_billing_first_name() . ' ' . $order->get_billing_last_name();
    $total = $order->get_total();
    $currency = $order->get_currency();
    $item_count = $order->get_item_count();

    // Format Professional Message
    $title = "🏷️ NEW ORDER RECEIVED • $currency " . number_format((float)$total, 2);
    $body = trim($customer_name) . " placed an order of $item_count " . ($item_count == 1 ? 'item' : 'items') . " for $currency " . number_format((float)$total, 2);

    // Send the Push
    woopress_connector_push_v1($topic, $title, $body, [
        'order_id' => (string)$order_id,
        'title' => $title,
        'body' => $body,
    ]);
}


// ==============================================================================
// 4. FIREBASE V1 PUSH IMPLEMENTATION (Internal Engine)
// ==============================================================================

function woopress_connector_push_v1($topic, $title, $body, $data = []) {
    // IMPORTANT: Ensure this JSON file is included in the plugin ZIP
    $service_account_file = plugin_dir_path(__FILE__) . 'wooexpress-firebase-adminsdk-fbsvc-849327c65f.json';
    $access_token = woopress_connector_get_token($service_account_file);
    
    if (!$access_token) {
        file_put_contents(plugin_dir_path(__FILE__) . 'woopress-node-error.log', date('Y-m-d H:i:s') . " | FCM ERROR: Missing or invalid Firebase JSON credentials.\n", FILE_APPEND);
        return false;
    }

    $project_id = 'wooexpress'; // Corrected Project ID
    $url = "https://fcm.googleapis.com/v1/projects/$project_id/messages:send";

    $payload = [
        'message' => [
            'topic' => $topic,
            'notification' => [
                'title' => $title,
                'body' => $body,
            ],
            'data' => $data,
            'android' => [
                'priority' => 'high',
                'notification' => [
                    'channel_id' => 'sales_alerts_v2',
                    'sound' => 'cash_register',
                    'click_action' => 'FLUTTER_NOTIFICATION_CLICK',
                    'icon' => 'ic_notification',
                ]
            ],
            'apns' => [
                'payload' => [
                    'aps' => [
                        'sound' => 'cash_register.wav',
                        'badge' => 1,
                    ]
                ]
            ]
        ]
    ];

    $response = wp_remote_post($url, [
        'headers' => [
            'Authorization' => 'Bearer ' . $access_token,
            'Content-Type' => 'application/json',
        ],
        'body' => json_encode($payload),
    ]);

    $code = wp_remote_retrieve_response_code($response);
    if ($code !== 200) {
        $error_body = wp_remote_retrieve_body($response);
        file_put_contents(plugin_dir_path(__FILE__) . 'woopress-node-error.log', date('Y-m-d H:i:s') . " | FCM SEND ERROR ($code): $error_body\n", FILE_APPEND);
        return false;
    }

    return true;
}

function woopress_base64url_encode($data) {
    return rtrim(strtr(base64_encode($data), '+/', '-_'), '=');
}

/**
 * JWT Auth Helper (Generates Google OAuth Token directly from PHP)
 */
function woopress_connector_get_token($file) {
    if (!file_exists($file)) {
        file_put_contents(plugin_dir_path(__FILE__) . 'woopress-node-error.log', date('Y-m-d H:i:s') . " | OAuth ERROR: Missing JSON file at $file\n", FILE_APPEND);
        return false;
    }
    $d = json_decode(file_get_contents($file), true);
    if (!$d || !isset($d['client_email']) || !isset($d['private_key'])) {
        file_put_contents(plugin_dir_path(__FILE__) . 'woopress-node-error.log', date('Y-m-d H:i:s') . " | OAuth ERROR: Invalid JSON format\n", FILE_APPEND);
        return false;
    }

    $h = woopress_base64url_encode(json_encode(['alg'=>'RS256','typ'=>'JWT']));
    
    $now = time() - 60; 
    $p = woopress_base64url_encode(json_encode([
        'iss' => $d['client_email'],
        'scope' => 'https://www.googleapis.com/auth/firebase.messaging',
        'aud' => 'https://oauth2.googleapis.com/token',
        'exp' => $now + 3600,
        'iat' => $now
    ]));
    
    $s = '';
    if (!openssl_sign("$h.$p", $s, $d['private_key'], 'SHA256')) {
        file_put_contents(plugin_dir_path(__FILE__) . 'woopress-node-error.log', date('Y-m-d H:i:s') . " | OAuth ERROR: OpenSSL Sign Failed\n", FILE_APPEND);
        return false;
    }
    $s = woopress_base64url_encode($s);
    
    $jwt = "$h.$p.$s";
    
    $resp = wp_remote_post('https://oauth2.googleapis.com/token', [
        'body' => [
            'grant_type' => 'urn:ietf:params:oauth:grant-type:jwt-bearer',
            'assertion' => $jwt
        ]
    ]);
    
    if (is_wp_error($resp)) {
        file_put_contents(plugin_dir_path(__FILE__) . 'woopress-node-error.log', date('Y-m-d H:i:s') . " | OAuth Network ERROR: " . $resp->get_error_message() . "\n", FILE_APPEND);
        return false;
    }
    
    $code = wp_remote_retrieve_response_code($resp);
    $body_str = wp_remote_retrieve_body($resp);
    
    if ($code !== 200) {
        file_put_contents(plugin_dir_path(__FILE__) . 'woopress-node-error.log', date('Y-m-d H:i:s') . " | OAuth Rejection ($code): $body_str\n", FILE_APPEND);
        return false;
    }
    
    $body = json_decode($body_str, true);
    return $body['access_token'] ?? false;
}

// ==============================================================================
// 5. SMTP AND EMAIL CUSTOMIZATION SETTINGS
// ==============================================================================

// Enqueue Media for Settings Page
add_action('admin_enqueue_scripts', 'woopress_connector_admin_scripts');
function woopress_connector_admin_scripts($hook) {
    if ($hook === 'settings_page_woopress-connector') {
        wp_enqueue_media();
    }
}

// Register Admin Menu
add_action('admin_menu', 'woopress_connector_settings_page');
function woopress_connector_settings_page() {
    add_options_page('WooPress Connector', 'WooPress Connector', 'manage_options', 'woopress-connector', 'woopress_connector_settings_html');
}

// Register Settings
add_action('admin_init', 'woopress_connector_register_settings');
function woopress_connector_register_settings() {
    register_setting('woopress_connector_options', 'woopress_smtp_host');
    register_setting('woopress_connector_options', 'woopress_smtp_port');
    register_setting('woopress_connector_options', 'woopress_smtp_user');
    register_setting('woopress_connector_options', 'woopress_smtp_pass');
    register_setting('woopress_connector_options', 'woopress_smtp_from_email');
    register_setting('woopress_connector_options', 'woopress_smtp_from_name');
    register_setting('woopress_connector_options', 'woopress_custom_emails_enabled');
    register_setting('woopress_connector_options', 'woopress_email_logo');
}

function woopress_connector_settings_html() {
    if (!current_user_can('manage_options')) return;
    
    // Handle Test Email
    $test_status = '';
    if (isset($_POST['woopress_test_email']) && check_admin_referer('woopress_test_email_action')) {
        $to = sanitize_email($_POST['woopress_test_email_to']);
        if ($to) {
            $result = wp_mail($to, 'WooPress SMTP Test', 'If you are reading this, your SMTP configuration is working perfectly!');
            if ($result) {
                $test_status = '<div class="notice notice-success is-dismissible"><p>Test email sent successfully!</p></div>';
            } else {
                global $ts_mail_errors;
                $err = isset($ts_mail_errors) ? $ts_mail_errors : 'Unknown error. Check logs.';
                $test_status = '<div class="notice notice-error is-dismissible"><p>Failed to send test email. Error: ' . esc_html($err) . '</p></div>';
            }
        }
    }
    
    ?>
    <div class="wrap">
        <h1>WooPress Connector Settings</h1>
        <?php echo $test_status; ?>
        
        <form method="post" action="options.php">
            <?php settings_fields('woopress_connector_options'); ?>
            <table class="form-table">
                <tr>
                    <th scope="row">Enable Custom Emails</th>
                    <td>
                        <input type="checkbox" name="woopress_custom_emails_enabled" value="1" <?php checked(1, get_option('woopress_custom_emails_enabled'), true); ?> />
                        <p class="description">Check this to override default WooCommerce Order Processing and Shipped emails with our modern beautiful designs.</p>
                    </td>
                </tr>
                <tr>
                    <th scope="row">Email Logo (Optional)</th>
                    <td>
                        <input type="text" name="woopress_email_logo" id="woopress_email_logo" value="<?php echo esc_attr(get_option('woopress_email_logo')); ?>" class="regular-text" />
                        <button class="button woopress_upload_logo_btn">Upload Logo</button>
                        <br><br>
                        <?php $logo_url = get_option('woopress_email_logo'); ?>
                        <img id="woopress_logo_preview" src="<?php echo esc_url($logo_url); ?>" style="max-height:60px; display: <?php echo $logo_url ? 'block' : 'none'; ?>;" />
                        <p class="description">Upload a logo to display in the header of custom emails.</p>
                    </td>
                </tr>
                <tr><th colspan="2"><h3>SMTP Configuration (e.g., Purelymail)</h3></th></tr>
                <tr>
                    <th scope="row">SMTP Host</th>
                    <td><input type="text" name="woopress_smtp_host" value="<?php echo esc_attr(get_option('woopress_smtp_host', 'smtp.purelymail.com')); ?>" class="regular-text" /></td>
                </tr>
                <tr>
                    <th scope="row">SMTP Port</th>
                    <td><input type="number" name="woopress_smtp_port" value="<?php echo esc_attr(get_option('woopress_smtp_port', '465')); ?>" class="small-text" /></td>
                </tr>
                <tr>
                    <th scope="row">SMTP Username</th>
                    <td><input type="text" name="woopress_smtp_user" value="<?php echo esc_attr(get_option('woopress_smtp_user')); ?>" class="regular-text" /></td>
                </tr>
                <tr>
                    <th scope="row">SMTP Password</th>
                    <td><input type="password" name="woopress_smtp_pass" value="<?php echo esc_attr(get_option('woopress_smtp_pass')); ?>" class="regular-text" /></td>
                </tr>
                <tr>
                    <th scope="row">From Email</th>
                    <td><input type="email" name="woopress_smtp_from_email" value="<?php echo esc_attr(get_option('woopress_smtp_from_email', get_option('admin_email'))); ?>" class="regular-text" /></td>
                </tr>
                <tr>
                    <th scope="row">From Name</th>
                    <td><input type="text" name="woopress_smtp_from_name" value="<?php echo esc_attr(get_option('woopress_smtp_from_name', get_option('blogname'))); ?>" class="regular-text" /></td>
                </tr>
            </table>
            <?php submit_button(); ?>
        </form>

        <hr>
        <h2>Test SMTP Connection</h2>
        <form method="post" action="">
            <?php wp_nonce_field('woopress_test_email_action'); ?>
            <table class="form-table">
                <tr>
                    <th scope="row">Send Test To</th>
                    <td>
                        <input type="email" name="woopress_test_email_to" value="<?php echo esc_attr(get_option('admin_email')); ?>" class="regular-text" required />
                    </td>
                </tr>
            </table>
            <p class="submit"><input type="submit" name="woopress_test_email" id="woopress_test_email" class="button button-secondary" value="Send Test Email"  /></p>
        </form>
    </div>
    <script>
    jQuery(document).ready(function($){
        $('.woopress_upload_logo_btn').click(function(e) {
            e.preventDefault();
            var custom_uploader = wp.media({
                title: 'Choose Logo',
                button: { text: 'Select Logo' },
                multiple: false
            }).on('select', function() {
                var attachment = custom_uploader.state().get('selection').first().toJSON();
                $('#woopress_email_logo').val(attachment.url);
                $('#woopress_logo_preview').attr('src', attachment.url).show();
            }).open();
        });
    });
    </script>
    <?php
}

// Hook into PHPMailer
add_action('phpmailer_init', 'woopress_connector_smtp_init');
function woopress_connector_smtp_init($phpmailer) {
    $host = get_option('woopress_smtp_host');
    $user = get_option('woopress_smtp_user');
    $pass = get_option('woopress_smtp_pass');
    
    if (!$host || !$user || !$pass) return; // Don't override if not configured

    $phpmailer->isSMTP();
    $phpmailer->Host       = $host;
    $phpmailer->SMTPAuth   = true;
    $phpmailer->Port       = get_option('woopress_smtp_port', 465);
    $phpmailer->Username   = $user;
    $phpmailer->Password   = $pass;
    $phpmailer->SMTPSecure = $phpmailer->Port == 465 ? 'ssl' : 'tls';
    $phpmailer->From       = get_option('woopress_smtp_from_email');
    $phpmailer->FromName   = get_option('woopress_smtp_from_name');
}

// Track mailer errors for debugging
add_action('wp_mail_failed', function($error) {
    global $ts_mail_errors;
    $ts_mail_errors = $error->get_error_message();
    file_put_contents(plugin_dir_path(__FILE__) . 'woopress-node-error.log', date('Y-m-d H:i:s') . " | SMTP ERROR: " . $error->get_error_message() . "\n", FILE_APPEND);
});

// ==============================================================================
// 6. CUSTOM WOOCOMMERCE EMAILS & TRACKING METABOX
// ==============================================================================

add_filter('woocommerce_email_classes', 'woopress_register_custom_emails');
function woopress_register_custom_emails($email_classes) {
    if (get_option('woopress_custom_emails_enabled')) {
        // Disable default emails to prevent duplicates
        if (isset($email_classes['WC_Email_Customer_Processing_Order'])) {
            remove_action('woocommerce_order_status_pending_to_processing_notification', array($email_classes['WC_Email_Customer_Processing_Order'], 'trigger'), 10, 2);
            remove_action('woocommerce_order_status_pending_to_on-hold_notification', array($email_classes['WC_Email_Customer_Processing_Order'], 'trigger'), 10, 2);
        }
        if (isset($email_classes['WC_Email_Customer_Completed_Order'])) {
            remove_action('woocommerce_order_status_completed_notification', array($email_classes['WC_Email_Customer_Completed_Order'], 'trigger'), 10, 2);
        }
        
        $processing_file = plugin_dir_path(__FILE__) . 'includes/emails/class-wc-custom-processing-email.php';
        $shipped_file = plugin_dir_path(__FILE__) . 'includes/emails/class-wc-custom-shipped-email.php';
        
        if (file_exists($processing_file) && file_exists($shipped_file)) {
            require_once $processing_file;
            require_once $shipped_file;
            
            $email_classes['WC_Custom_Processing_Email'] = new WC_Custom_Processing_Email();
            $email_classes['WC_Custom_Shipped_Email'] = new WC_Custom_Shipped_Email();
        } else {
            error_log("WooPress Connector Error: Custom email class files are missing.");
        }
    }
    return $email_classes;
}

// Add Tracking Meta Box in WordPress Admin
add_action('add_meta_boxes', 'woopress_tracking_meta_box');
function woopress_tracking_meta_box() {
    add_meta_box('woopress_tracking_box', 'Shipment Tracking', 'woopress_tracking_box_html', 'shop_order', 'side', 'core');
    add_meta_box('woopress_tracking_box', 'Shipment Tracking', 'woopress_tracking_box_html', 'woocommerce_page_wc-orders', 'side', 'core');
}

function woopress_tracking_box_html($post_or_order) {
    $order = ($post_or_order instanceof WP_Post) ? wc_get_order($post_or_order->ID) : $post_or_order;
    if (!$order) return;
    
    $tracking_number = $order->get_meta('_tracking_number');
    $tracking_courier = $order->get_meta('_tracking_courier');
    ?>
    <p>
        <label><strong>Tracking Number:</strong></label><br/>
        <input type="text" name="woopress_tracking_number" value="<?php echo esc_attr($tracking_number); ?>" style="width:100%;"/>
    </p>
    <p>
        <label><strong>Courier:</strong></label><br/>
        <input type="text" name="woopress_tracking_courier" value="<?php echo esc_attr($tracking_courier); ?>" style="width:100%;"/>
    </p>
    <?php
}

add_action('woocommerce_process_shop_order_meta', 'woopress_save_tracking_meta_hpos', 10, 2);
function woopress_save_tracking_meta_hpos($order_id, $post = null) {
    $order = wc_get_order($order_id);
    if (!$order) return;
    $changed = false;
    if (isset($_POST['woopress_tracking_number'])) {
        $order->update_meta_data('_tracking_number', sanitize_text_field($_POST['woopress_tracking_number']));
        $changed = true;
    }
    if (isset($_POST['woopress_tracking_courier'])) {
        $order->update_meta_data('_tracking_courier', sanitize_text_field($_POST['woopress_tracking_courier']));
        $changed = true;
    }
    if ($changed) $order->save();
}

// ==============================================================================
// 7. DASHBOARD STATS API ENDPOINT
// ==============================================================================

add_action('rest_api_init', function () {
    register_rest_route('wc/v3', '/woopress-dashboard', array(
        'methods' => 'GET',
        'callback' => 'woopress_get_dashboard_stats',
        'permission_callback' => function (\WP_REST_Request $request) {
            return current_user_can('read_private_shop_orders') || current_user_can('manage_woocommerce');
        }
    ));
});

function woopress_get_dashboard_stats() {
    global $wpdb;
    
    $orders_table = $wpdb->prefix . 'wc_orders';
    $is_hpos = $wpdb->get_var("SHOW TABLES LIKE '$orders_table'") === $orders_table;
    
    $today_start = gmdate('Y-m-d 00:00:00');
    $month_start = gmdate('Y-m-01 00:00:00');
    $year_start = gmdate('Y-01-01 00:00:00');
    
    // Get visitors count from existing vibe-coded tracker
    $today_visitors = current_time('Ymd');
    $visitors = get_transient('woopress_daily_visitors_' . $today_visitors) ?: 0;

    $stats = array(
        'todayRevenue' => 0.0,
        'monthlyRevenue' => 0.0,
        'yearlyRevenue' => 0.0,
        'ordersToday' => 0,
        'itemsSold' => 0,
        'visitorsToday' => (int)$visitors
    );
    
    if ($is_hpos) {
        $sql = "SELECT date_created_gmt, total_amount 
                FROM {$orders_table} 
                WHERE date_created_gmt >= %s 
                AND status NOT IN ('wc-cancelled', 'wc-refunded', 'wc-failed')";
        
        $results = $wpdb->get_results($wpdb->prepare($sql, $year_start));
        
        foreach ($results as $row) {
            $total = (float) $row->total_amount;
            $date = $row->date_created_gmt;
            $stats['yearlyRevenue'] += $total;
            if ($date >= $month_start) $stats['monthlyRevenue'] += $total;
            if ($date >= $today_start) {
                $stats['todayRevenue'] += $total;
                $stats['ordersToday']++;
            }
        }
        
        $items_sql = "SELECT SUM(woi.product_qty) 
                      FROM {$wpdb->prefix}woocommerce_order_items woi
                      JOIN {$orders_table} o ON o.id = woi.order_id
                      WHERE woi.order_item_type = 'line_item'
                      AND o.date_created_gmt >= %s
                      AND o.status NOT IN ('wc-cancelled', 'wc-refunded', 'wc-failed')";
        $stats['itemsSold'] = (int) $wpdb->get_var($wpdb->prepare($items_sql, $today_start));
        
    } else {
        $sql = "SELECT p.post_date_gmt as date_created_gmt, 
                       (SELECT meta_value FROM {$wpdb->postmeta} WHERE post_id = p.ID AND meta_key = '_order_total' LIMIT 1) as total_amount
                FROM {$wpdb->posts} p
                WHERE p.post_type = 'shop_order' 
                AND p.post_date_gmt >= %s 
                AND p.post_status NOT IN ('wc-cancelled', 'wc-refunded', 'wc-failed')";
                
        $results = $wpdb->get_results($wpdb->prepare($sql, $year_start));
        
        foreach ($results as $row) {
            $total = (float) $row->total_amount;
            $date = $row->date_created_gmt;
            $stats['yearlyRevenue'] += $total;
            if ($date >= $month_start) $stats['monthlyRevenue'] += $total;
            if ($date >= $today_start) {
                $stats['todayRevenue'] += $total;
                $stats['ordersToday']++;
            }
        }
        
        $items_sql = "SELECT SUM(woi.product_qty) 
                      FROM {$wpdb->prefix}woocommerce_order_items woi
                      JOIN {$wpdb->posts} o ON o.ID = woi.order_id
                      WHERE woi.order_item_type = 'line_item'
                      AND o.post_date_gmt >= %s
                      AND o.post_status NOT IN ('wc-cancelled', 'wc-refunded', 'wc-failed')";
        $stats['itemsSold'] = (int) $wpdb->get_var($wpdb->prepare($items_sql, $today_start));
    }
    
    return rest_ensure_response(array('success' => true, 'data' => $stats));
}
