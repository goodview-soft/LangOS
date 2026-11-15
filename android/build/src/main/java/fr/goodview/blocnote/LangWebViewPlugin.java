package fr.goodview.blocnote;

import android.app.Activity;
import android.view.Gravity;
import android.view.View;
import android.webkit.CookieManager;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.FrameLayout;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.SignalInfo;
import org.godotengine.godot.plugin.UsedByGodot;

import java.util.Collections;
import java.util.Set;

/** WebView Android (Chromium du système) superposé à la zone « page » de la fenêtre navigateur de LangOS. */
public class LangWebViewPlugin extends GodotPlugin {
	private static final SignalInfo URL_CHANGED = new SignalInfo("url_changed", String.class);
	private static final SignalInfo PAGE_TEXT = new SignalInfo("page_text", String.class);
	private WebView web;

	public LangWebViewPlugin(Godot godot) {
		super(godot);
	}

	@Override
	public String getPluginName() {
		return "LangWebView";
	}

	@Override
	public Set<SignalInfo> getPluginSignals() {
		return new java.util.HashSet<>(java.util.Arrays.asList(URL_CHANGED, PAGE_TEXT));
	}

	private FrameLayout.LayoutParams params(int x, int y, int w, int h) {
		FrameLayout.LayoutParams lp = new FrameLayout.LayoutParams(Math.max(w, 1), Math.max(h, 1));
		lp.gravity = Gravity.TOP | Gravity.LEFT;
		lp.leftMargin = x;
		lp.topMargin = y;
		return lp;
	}

	@UsedByGodot
	public void open(final String url, final int x, final int y, final int w, final int h) {
		final Activity a = getActivity();
		if (a == null) return;
		a.runOnUiThread(() -> {
			if (web == null) {
				web = new WebView(a);
				WebSettings s = web.getSettings();
				s.setJavaScriptEnabled(true);
				s.setDomStorageEnabled(true);
				s.setLoadWithOverviewMode(true);
				s.setBuiltInZoomControls(true);
				s.setDisplayZoomControls(false);
				CookieManager.getInstance().setAcceptCookie(true);
				web.setWebViewClient(new WebViewClient() {
					@Override
					public void onPageStarted(WebView v, String u, android.graphics.Bitmap f) {
						emitSignal(URL_CHANGED, u);
					}

					@Override
					public void onPageFinished(WebView v, String u) {
						emitSignal(URL_CHANGED, u);
					}
				});
				a.addContentView(web, params(x, y, w, h));
			} else {
				web.setLayoutParams(params(x, y, w, h));
			}
			web.loadUrl(url);
		});
	}

	@UsedByGodot
	public void place(final int x, final int y, final int w, final int h) {
		final Activity a = getActivity();
		if (a == null) return;
		a.runOnUiThread(() -> { if (web != null) web.setLayoutParams(params(x, y, w, h)); });
	}

	@UsedByGodot
	public void setShown(final boolean shown) {
		final Activity a = getActivity();
		if (a == null) return;
		a.runOnUiThread(() -> { if (web != null) web.setVisibility(shown ? View.VISIBLE : View.INVISIBLE); });
	}

	@UsedByGodot
	public void load(final String url) {
		final Activity a = getActivity();
		if (a == null) return;
		a.runOnUiThread(() -> { if (web != null) web.loadUrl(url); });
	}

	@UsedByGodot
	public void getText() {
		final Activity a = getActivity();
		if (a == null) return;
		a.runOnUiThread(() -> {
			if (web == null) { emitSignal(PAGE_TEXT, ""); return; }
			web.evaluateJavascript("(function(){return document.body ? document.body.innerText : ''})()", value -> emitSignal(PAGE_TEXT, value == null ? "" : value));
		});
	}

	@UsedByGodot
	public void back() {
		final Activity a = getActivity();
		if (a == null) return;
		a.runOnUiThread(() -> { if (web != null && web.canGoBack()) web.goBack(); });
	}

	@UsedByGodot
	public void forward() {
		final Activity a = getActivity();
		if (a == null) return;
		a.runOnUiThread(() -> { if (web != null && web.canGoForward()) web.goForward(); });
	}

	@UsedByGodot
	public void reload() {
		final Activity a = getActivity();
		if (a == null) return;
		a.runOnUiThread(() -> { if (web != null) web.reload(); });
	}

	@UsedByGodot
	public void close() {
		final Activity a = getActivity();
		if (a == null) return;
		a.runOnUiThread(() -> {
			if (web != null) {
				((android.view.ViewGroup) web.getParent()).removeView(web);
				web.destroy();
				web = null;
			}
		});
	}
}
