using Gtk;

[GtkTemplate (ui = "/com/github/bleakgrey/tootle/ui/dialogs/compose.ui")]
public class Tootle.Dialogs.Compose : Window {

    public API.Status? status { get; construct set; }
    public string style_class { get; construct set; }
    public string label { get; construct set; }
    public int char_limit {
        get {
            return 250;
        }
    }

    [GtkChild]
    protected Box box;
    
    [GtkChild]
    protected Revealer cw_revealer;
    [GtkChild]
    protected ToggleButton cw_button;
    [GtkChild]
    protected Entry cw;
    [GtkChild]
    protected Label counter;
    
    [GtkChild]
    protected MenuButton visibility_button;
    [GtkChild]
    protected Image visibility_icon;
    protected Widgets.VisibilityPopover visibility_popover;
    [GtkChild]
    protected Button post_button;
    
    [GtkChild]
    protected TextView content;

    construct {
        transient_for = window;
        
        post_button.label = label;
		foreach (Widget w in new Widget[] { visibility_button, post_button })
			w.get_style_context ().add_class (style_class);
        
        visibility_popover = new Widgets.VisibilityPopover.with_button (visibility_button);
        visibility_popover.bind_property ("selected", visibility_icon, "icon-name", BindingFlags.SYNC_CREATE, (b, src, ref target) => {
			target.set_string (((API.Visibility)src).get_icon ());
			return true;
		});
        
        cw_button.bind_property ("active", cw_revealer, "reveal_child", BindingFlags.SYNC_CREATE);
        
        cw_button.toggled.connect (validate);
        cw.buffer.deleted_text.connect (() => validate ());
        cw.buffer.inserted_text.connect (() => validate ());
        content.buffer.changed.connect (validate);
        post_button.clicked.connect (on_post_button_clicked);
        
        if (status.spoiler_text != null) {
            cw.text = status.spoiler_text;
            cw_button.active = true;
        }
        content.buffer.text = Html.remove_tags (status.content);
        
        show ();
    }

    public Compose () {
        Object (status: new API.Status (-1), style_class: STYLE_CLASS_SUGGESTED_ACTION, label: _("Post"));
    }
    
    public Compose.redraft (API.Status status) {
        Object (status: status, style_class: STYLE_CLASS_DESTRUCTIVE_ACTION, label: _("Redraft"));
    }

	public Compose.reply (API.Status status) {
		var template = new API.Status (-1);
		template.in_reply_to_id = status.in_reply_to_id;
		template.in_reply_to_account_id = status.in_reply_to_account_id;
		template.content = status.formal.get_reply_mentions ();
		Object (status: template, style_class: STYLE_CLASS_SUGGESTED_ACTION, label: _("Reply"));
		visibility_popover.selected = status.visibility;
	}

    protected void validate () {
        var remain = char_limit - content.buffer.get_char_count ();
        if (cw_button.active)
            remain -= (int)cw.buffer.length;

        counter.label = remain.to_string ();
        post_button.sensitive = remain >= 0;
        visibility_button.sensitive = true;
        box.sensitive = true;
    }
    
    protected void on_error (int32 code, string reason) { //TODO: display errors
        warning (reason);
        validate ();
    }
    
    protected void on_post_button_clicked () {
        post_button.sensitive = false;
        visibility_button.sensitive = false;
        box.sensitive = false;
        
        if (status.id >= 0) {
            info ("Removing old status...");
            status.poof (publish, on_error);
        }
        else {
            publish ();
        }
    }
    
    protected void publish () {
        info ("Publishing new status...");
        status.content = content.buffer.text;
        status.spoiler_text = cw.text;

        var req = new Request.POST ("/api/v1/statuses")
            .with_account ()
            .with_param ("visibility", visibility_popover.selected.to_string ())
            .with_param ("status", Html.uri_encode (status.content));
            
        if (cw_button.active) {
            req.with_param ("sensitive", "true");
            req.with_param ("spoiler_text", Html.uri_encode (cw.text));
        }

        if (status.in_reply_to_id != null)
            req.with_param ("in_reply_to_id", status.in_reply_to_id);
        if (status.in_reply_to_account_id != null)
            req.with_param ("in_reply_to_account_id", status.in_reply_to_account_id);
        
        req.then ((sess, mess) => {
            var root = network.parse (mess);
            var status = API.Status.parse (root);
            info ("OK: status id is %s", status.id.to_string ());
            destroy ();
        })
        .on_error (on_error)
        .exec ();
    }

}
