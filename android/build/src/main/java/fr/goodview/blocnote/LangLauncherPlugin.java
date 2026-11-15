package fr.goodview.blocnote;

import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.drawable.Drawable;
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
