package fr.goodview.blocnote;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;

/**
 * Point d'entrée unique (icône de l'appli ET écran d'accueil). Godot ne supporte pas deux instances dans le même processus :
 * Android crée pourtant une tâche « accueil » distincte de la tâche « appli ». Cette activité transparente renvoie
 * donc toujours vers l'unique GodotApp (créée ou ramenée au premier plan) puis se ferme.
 */
public class EntryActivity extends Activity {
	@Override
	protected void onCreate(Bundle savedInstanceState) {
		super.onCreate(savedInstanceState);
		Intent i = new Intent(this, com.godot.game.GodotApp.class);
		i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_REORDER_TO_FRONT);
		if (getIntent() != null && getIntent().getExtras() != null) i.putExtras(getIntent().getExtras());
		startActivity(i);
		finish();
	}
}
