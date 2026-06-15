<?php
if ( ! defined( 'ABSPATH' ) ) exit;

class WC_Custom_Processing_Email extends WC_Email {

    public function __construct() {
        $this->id             = 'woopress_customer_processing_order';
        $this->title          = 'Custom Processing Order';
        $this->description    = 'This is an order notification sent to customers containing order details after payment.';
        $this->template_html  = 'emails/modern-processing.php';
        $this->template_base  = plugin_dir_path( dirname( __DIR__ ) ) . 'templates/';
        $this->placeholders   = array(
            '{site_title}'   => $this->get_blogname(),
            '{order_date}'   => '',
            '{order_number}' => '',
        );

        parent::__construct();
        
        $this->customer_email = true;
        
        // Triggers
        add_action( 'woocommerce_order_status_pending_to_processing_notification', array( $this, 'trigger' ), 10, 2 );
        add_action( 'woocommerce_order_status_pending_to_on-hold_notification', array( $this, 'trigger' ), 10, 2 );
    }

    public function get_default_subject() {
        return "We've Received Your Order #{order_number}";
    }

    public function get_default_heading() {
        return 'Thank you for your order';
    }

    public function trigger( $order_id, $order = false ) {
        $this->setup_locale();
        if ( $order_id && ! is_a( $order, 'WC_Order' ) ) {
            $order = wc_get_order( $order_id );
        }
        if ( is_a( $order, 'WC_Order' ) ) {
            $this->object                         = $order;
            $this->recipient                      = $this->object->get_billing_email();
            $this->placeholders['{order_date}']   = wc_format_datetime( $this->object->get_date_created() );
            $this->placeholders['{order_number}'] = $this->object->get_order_number();
        }

        if ( $this->is_enabled() && $this->get_recipient() ) {
            $this->send( $this->get_recipient(), $this->get_subject(), $this->get_content(), $this->get_headers(), $this->get_attachments() );
        }
        $this->restore_locale();
    }

    public function get_content_html() {
        ob_start();
        wc_get_template( $this->template_html, array(
            'order'         => $this->object,
            'email_heading' => $this->get_heading(),
            'sent_to_admin' => false,
            'plain_text'    => false,
            'email'         => $this,
        ), '', $this->template_base );
        return ob_get_clean();
    }
}
