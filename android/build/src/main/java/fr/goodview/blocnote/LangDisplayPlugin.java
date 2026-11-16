package fr.goodview.blocnote;

import android.app.Activity;
import android.app.ActivityOptions;
import android.app.Presentation;
import android.content.Context;
import android.content.Intent;
import android.graphics.Color;
import android.hardware.display.DisplayManager;
import android.view.Display;
import android.view.Gravity;
import android.view.WindowManager;
import android.widget.TextView;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.UsedByGodot;
import org.json.JSONArray;
import org.json.JSONObject;

/** Test multi-écrans (Flip : écran de couverture + écran interne) : liste des écrans, contenu sur un autre écran, activité sur un autre écran. */
public class LangDisplayPlugin extends GodotPlugin {
	private Presentation pres;

	public LangDisplayPlugin(Godot godot) { super(godot); }

	@Override public String getPluginName() { return "LangDisplay"; }

	private static String stateName(int s) {
		switch (s) {
			case Display.STATE_OFF: return "éteint";
			case Display.STATE_ON: return "allumé";
			case Display.STATE_DOZE: return "veille";
			case Display.STATE_DOZE_SUSPEND: return "veille+";
			case Display.STATE_VR: return "VR";
			case Display.STATE_ON_SUSPEND: return "allumé+";
			default: return "?";
		}
	}

	/** JSON : [{id, name, state, w, h, flags, presentation, current}] — y compris les écrans éteints. */
	@UsedByGodot
	public String listDisplays() {
		Activity a = getActivity();
		JSONArray arr = new JSONArray();
		if (a == null) return arr.toString();
		DisplayManager dm = (DisplayManager) a.getSystemService(Context.DISPLAY_SERVICE);
		int cur = a.getWindowManager().getDefaultDisplay().getDisplayId();
		java.util.Set<Integer> pres = new java.util.HashSet<>();
		for (Display d : dm.getDisplays(DisplayManager.DISPLAY_CATEGORY_PRESENTATION)) pres.add(d.getDisplayId());
		try {
			for (Display d : dm.getDisplays()) {
				android.graphics.Point p = new android.graphics.Point();
				d.getRealSize(p);
				JSONObject o = new JSONObject();
				o.put("id", d.getDisplayId());
				o.put("name", d.getName());
				o.put("state", stateName(d.getState()));
				o.put("w", p.x); o.put("h", p.y);
				o.put("flags", d.getFlags());
				o.put("presentation", pres.contains(d.getDisplayId()));
				o.put("current", d.getDisplayId() == cur);
				arr.put(o);
			}
		} catch (Exception e) { }
		return arr.toString();
	}

	/** Affiche un texte plein écran sur l'écran donné (Presentation). Renvoie "ok" ou l'erreur. */
	@UsedByGodot
	public String showOn(final int displayId, final String text, final String color) {
		final Activity a = getActivity();
		if (a == null) return "pas d'activité";
		final String[] res = {"ok"};
		final Object lock = new Object();
		a.runOnUiThread(() -> {
			try {
				if (pres != null) { try { pres.dismiss(); } catch (Exception e) { } pres = null; }
				DisplayManager dm = (DisplayManager) a.getSystemService(Context.DISPLAY_SERVICE);
				Display d = dm.getDisplay(displayId);
				if (d == null) { res[0] = "écran " + displayId + " introuvable"; }
				else {
					Presentation p = new Presentation(a, d);
					TextView tv = new TextView(p.getContext());
					tv.setText(text); tv.setTextSize(28); tv.setGravity(Gravity.CENTER); tv.setTextColor(Color.WHITE);
					tv.setBackgroundColor(Color.parseColor(color));
					p.setContentView(tv);
					p.show();
					pres = p;
				}
			} catch (Exception e) {
				res[0] = e.getClass().getSimpleName() + ": " + e.getMessage();
			}
			synchronized (lock) { lock.notifyAll(); }
		});
		synchronized (lock) { try { lock.wait(1500); } catch (InterruptedException e) { } }
		return res[0];
	}

	@UsedByGodot
	public void hideOn() {
		final Activity a = getActivity();
		if (a == null) return;
		a.runOnUiThread(() -> { if (pres != null) { try { pres.dismiss(); } catch (Exception e) { } pres = null; } });
	}

	/** Lance LangOS dans une nouvelle tâche sur l'écran donné. Renvoie "ok" ou l'erreur. */
	@UsedByGodot
	public String launchOn(int displayId) {
		Activity a = getActivity();
		if (a == null) return "pas d'activité";
		try {
			Intent i = a.getPackageManager().getLaunchIntentForPackage(a.getPackageName());
			if (i == null) return "pas d'intent de lancement";
			i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_MULTIPLE_TASK);
			ActivityOptions o = ActivityOptions.makeBasic();
			o.setLaunchDisplayId(displayId);
			a.startActivity(i, o.toBundle());
			return "ok";
		} catch (Exception e) {
			return e.getClass().getSimpleName() + ": " + e.getMessage();
		}
	}

	/** Garde l'écran allumé tant que l'appli est visible. */
	@UsedByGodot
	public void keepAwake(final boolean on) {
		final Activity a = getActivity();
		if (a == null) return;
		a.runOnUiThread(() -> {
			if (on) a.getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
			else a.getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
		});
	}
}
