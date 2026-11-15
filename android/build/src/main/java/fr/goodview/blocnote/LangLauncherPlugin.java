package fr.goodview.blocnote;

import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.content.IntentFilter;
import android.graphics.drawable.Drawable;
import android.net.ConnectivityManager;
import android.net.Network;
import android.net.NetworkCapabilities;
import android.net.wifi.WifiInfo;
import android.net.wifi.WifiManager;
import android.os.BatteryManager;
import android.provider.Settings;
import android.util.Base64;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.UsedByGodot;
import org.json.JSONArray;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/** Lanceur : liste les applications installées (avec icônes), les lance, et ouvre le choix de l'écran d'accueil. */
public class LangLauncherPlugin extends GodotPlugin {
	public LangLauncherPlugin(Godot godot) {
		super(godot);
	}

	@Override
	public String getPluginName() {
		return "LangLauncher";
	}

	/** Niveau de la partie native de cette APK (comparé à version.json « native » pour proposer de réinstaller l'APK). */
	@UsedByGodot
	public int nativeLevel() {
		return 6;
	}

	/** JSON d'état système : {"battery":%, "charging":bool, "net":"wifi|cell|eth|none", "level":0..3} (barre des tâches). */
	@UsedByGodot
	public String systemStatus() {
		JSONObject o = new JSONObject();
		Activity a = getActivity();
		try {
			if (a == null) return "{}";
			Intent b = a.registerReceiver(null, new IntentFilter(Intent.ACTION_BATTERY_CHANGED));
			int pct = -1;
			boolean charging = false;
			if (b != null) {
				int lv = b.getIntExtra(BatteryManager.EXTRA_LEVEL, -1);
				int sc = b.getIntExtra(BatteryManager.EXTRA_SCALE, 100);
				if (lv >= 0 && sc > 0) pct = lv * 100 / sc;
				int st = b.getIntExtra(BatteryManager.EXTRA_STATUS, -1);
				charging = st == BatteryManager.BATTERY_STATUS_CHARGING || st == BatteryManager.BATTERY_STATUS_FULL;
			}
			o.put("battery", pct);
			o.put("charging", charging);
			String net = "none";
			int level = 3;
			try {
				ConnectivityManager cm = (ConnectivityManager) a.getSystemService(android.content.Context.CONNECTIVITY_SERVICE);
				Network n = cm.getActiveNetwork();
				NetworkCapabilities nc = n == null ? null : cm.getNetworkCapabilities(n);
				if (nc != null) {
					if (nc.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) net = "wifi";
					else if (nc.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)) net = "cell";
					else if (nc.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)) net = "eth";
				}
				if (net.equals("wifi")) {
					WifiManager wm = (WifiManager) a.getApplicationContext().getSystemService(android.content.Context.WIFI_SERVICE);
					WifiInfo wi = wm.getConnectionInfo();
					if (wi != null) level = WifiManager.calculateSignalLevel(wi.getRssi(), 4);
				}
			} catch (Exception e) {
				// état réseau indisponible : on garde « none »
			}
			o.put("net", net);
			o.put("level", level);
		} catch (Exception e) {
			return "{}";
		}
		return o.toString();
	}

	/** JSON : [{"label":..., "pkg":..., "icon":"<png base64>"}], trié par nom, sans LangOS lui-même. */
	@UsedByGodot
	public String listApps(int iconSize) {
		Activity a = getActivity();
		if (a == null) return "[]";
		PackageManager pm = a.getPackageManager();
		Intent main = new Intent(Intent.ACTION_MAIN, null);
		main.addCategory(Intent.CATEGORY_LAUNCHER);
		List<ResolveInfo> list = pm.queryIntentActivities(main, 0);
		final List<String[]> rows = new ArrayList<>();
		for (ResolveInfo ri : list) {
			String pkg = ri.activityInfo.packageName;
			if (pkg.equals(a.getPackageName())) continue;
			String label = String.valueOf(ri.loadLabel(pm));
			String icon = "";
			try {
				Drawable d = ri.loadIcon(pm);
				Bitmap bmp = Bitmap.createBitmap(iconSize, iconSize, Bitmap.Config.ARGB_8888);
				Canvas c = new Canvas(bmp);
				d.setBounds(0, 0, iconSize, iconSize);
				d.draw(c);
				ByteArrayOutputStream bo = new ByteArrayOutputStream();
				bmp.compress(Bitmap.CompressFormat.PNG, 100, bo);
				icon = Base64.encodeToString(bo.toByteArray(), Base64.NO_WRAP);
			} catch (Exception e) {
				// icône absente : la tuile s'affichera sans image
			}
			rows.add(new String[] { label, pkg, icon });
		}
		Collections.sort(rows, (x, y) -> x[0].compareToIgnoreCase(y[0]));
		JSONArray out = new JSONArray();
		try {
			for (String[] r : rows) {
				JSONObject o = new JSONObject();
				o.put("label", r[0]);
				o.put("pkg", r[1]);
				o.put("icon", r[2]);
				out.put(o);
			}
		} catch (Exception e) {
			return "[]";
		}
		return out.toString();
	}

	@UsedByGodot
	public boolean launchApp(String pkg) {
		Activity a = getActivity();
		if (a == null) return false;
		Intent i = a.getPackageManager().getLaunchIntentForPackage(pkg);
		if (i == null) return false;
		i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
		a.startActivity(i);
		return true;
	}

	/** Ouvre un autre écran d'accueil que LangOS (le bureau Android d'origine), sans changer l'écran d'accueil par défaut. */
	@UsedByGodot
	public boolean launchOtherHome() {
		Activity a = getActivity();
		if (a == null) return false;
		PackageManager pm = a.getPackageManager();
		Intent home = new Intent(Intent.ACTION_MAIN);
		home.addCategory(Intent.CATEGORY_HOME);
		for (ResolveInfo ri : pm.queryIntentActivities(home, 0)) {
			if (ri.activityInfo.packageName.equals(a.getPackageName())) continue;
			Intent i = new Intent(Intent.ACTION_MAIN);
			i.addCategory(Intent.CATEGORY_HOME);
			i.setClassName(ri.activityInfo.packageName, ri.activityInfo.name);
			i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
			try {
				a.startActivity(i);
				return true;
			} catch (Exception e) {
				// on essaie le suivant
			}
		}
		return false;
	}

	/** Ouvre le réglage Android « application d'accueil » pour choisir LangOS. */
	@UsedByGodot
	public void chooseHome() {
		Activity a = getActivity();
		if (a == null) return;
		Intent i = new Intent(Settings.ACTION_HOME_SETTINGS);
		i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
		try {
			a.startActivity(i);
		} catch (Exception e) {
			a.startActivity(new Intent(Settings.ACTION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
		}
	}
}
