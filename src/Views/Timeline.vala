using Gtk;
using Gdk;

public class Tootle.Views.Timeline : Views.Base, IAccountListener, IStreamListener {

    public string timeline { get; construct set; }
    public bool is_public { get; construct set; default = false; }

    protected int limit = 25;
    protected bool is_last_page = false;
    protected string? page_next;
    protected string? page_prev;
    protected string? stream;

    construct {
        connect_account_service ();
        app.refresh.connect (on_refresh);
        status_button.clicked.connect (on_refresh);

        request ();
    }
    ~Timeline () {
        streams.unsubscribe (stream, this);
    }

    public override string get_icon () {
        return "user-home-symbolic";
    }

    public override string get_name () {
        return _("Home");
    }

    public override void on_status_added (API.Status status) {
        warning ("TIMELINE ON_STATUS_ADDED");
        prepend (status);
    }

    public virtual bool is_status_owned (API.Status status) {
        return status.is_owned ();
    }

    public void prepend (API.Status status) {
        append (status, true);
    }

    public void append (API.Status status, bool first = false) {
        var widget = new Widgets.Status (status);
        widget.button_press_event.connect (widget.open);
        if (!is_status_owned (status))
            widget.avatar.button_press_event.connect (widget.on_avatar_clicked);

        content.pack_start (widget, false, false, 0);
        if (first || status.pinned)
            content.reorder_child (widget, 0);

        on_content_changed ();
    }

    public override void clear () {
        this.page_prev = null;
        this.page_next = null;
        this.is_last_page = false;
        base.clear ();
    }

    public void get_pages (string? header) {
        page_next = page_prev = null;
        if (header == null)
            return;

        var pages = header.split (",");
        foreach (var page in pages) {
            var sanitized = page
                .replace ("<","")
                .replace (">", "")
                .split (";")[0];

            if ("rel=\"prev\"" in page)
                page_prev = sanitized;
            else
                page_next = sanitized;
        }

        is_last_page = page_prev != null & page_next == null;
    }

    public virtual string get_url () {
        if (page_next != null)
            return page_next;

        return @"/api/v1/timelines/$timeline";
    }

    public virtual Request append_params (Request req) {
        return req.with_param ("limit", limit.to_string ());
    }

    public virtual void request () {
        if (accounts.active == null) // TODO: Add account reference to IAccountListener
            return;

		append_params (new Request.GET (get_url ()))
		.with_account ()
		.then_parse_array ((node, msg) => {
            var obj = node.get_object ();
            if (obj != null) {
                var status = API.Status.parse (obj);
                append (status);
            }
            get_pages (msg.response_headers.get_one ("Link"));
        })
		.on_error (on_error)
		.exec ();
    }

    public virtual void on_refresh () {
        status_button.sensitive = false;
        clear ();
        request ();
    }

    public virtual string? get_stream_url () {
        return null;
    }

    public override void on_account_changed (InstanceAccount? account) {
		streams.unsubscribe (stream, this);
        if (account == null)
            return;

        if (can_stream ())
            streams.subscribe (get_stream_url (), this, out stream);

        on_refresh ();
    }

    protected virtual bool can_stream () {
        var allowed_public = true;
        if (is_public)
            allowed_public = settings.live_updates_public;

        return settings.live_updates && allowed_public;
    }

    protected override void on_bottom_reached () {
        if (is_last_page) {
            info ("Last page reached");
            return;
        }
        request ();
    }

}
