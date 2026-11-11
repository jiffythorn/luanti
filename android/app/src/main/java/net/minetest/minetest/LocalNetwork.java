/*
Kid Town phone client
Copyright (C) 2026 Kid Town contributors

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU Lesser General Public License as published by
the Free Software Foundation; either version 2.1 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Lesser General Public License for more details.

You should have received a copy of the GNU Lesser General Public License along
with this program; if not, see <https://www.gnu.org/licenses/>.
*/

package net.minetest.minetest;

import android.content.Context;
import android.net.ConnectivityManager;
import android.net.Network;
import android.net.NetworkCapabilities;
import android.net.NetworkRequest;
import android.os.Build;
import android.util.Log;

/**
 * Keeps this app on the local Wi-Fi network.
 *
 * Android normally routes an app's sockets over its "default" network. When
 * the home Wi-Fi has no internet (the normal Kid Town setup), Android can
 * decide the default is mobile data. A LAN server then looks unreachable, or
 * the app silently goes out to the internet over the cellular connection.
 *
 * bindProcessToNetwork() applies to the whole process, including the native
 * Luanti UDP sockets. We bind to the Wi-Fi transport explicitly, whether or
 * not that Wi-Fi has internet access. The native build also refuses any
 * non-LAN destination address (LOCAL_NETWORK_ONLY), so this is a two-layer
 * guarantee: the app uses Wi-Fi, and it never talks to the internet.
 */
final class LocalNetwork {
	private static final String TAG = "KidTownNetwork";

	private static ConnectivityManager sManager;
	private static ConnectivityManager.NetworkCallback sCallback;
	private static Network sBound;

	private LocalNetwork() {
	}

	/** Bind now and watch for Wi-Fi changes. Safe to call more than once. */
	static synchronized void start(Context context) {
		Context app = context.getApplicationContext();
		if (app == null)
			app = context;

		if (sManager == null)
			sManager = (ConnectivityManager) app.getSystemService(Context.CONNECTIVITY_SERVICE);
		if (sManager == null) {
			Log.w(TAG, "no ConnectivityManager; local Wi-Fi binding unavailable");
			return;
		}

		bindWifi();

		if (sCallback != null)
			return;

		sCallback = new ConnectivityManager.NetworkCallback() {
			@Override
			public void onAvailable(Network network) {
				bindWifi();
			}

			@Override
			public void onLost(Network network) {
				// Do not fall back to mobile data when Wi-Fi disappears.
				// Keep the old binding: game sockets then fail instead of
				// quietly leaving the local network. The next Wi-Fi network
				// is picked up by onAvailable()/onCapabilitiesChanged().
				Log.i(TAG, "Wi-Fi network lost; staying off mobile data");
			}

			@Override
			public void onCapabilitiesChanged(Network network,
					NetworkCapabilities capabilities) {
				bindWifi();
			}
		};

		NetworkRequest request = new NetworkRequest.Builder()
				.addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
				.build();
		try {
			sManager.registerNetworkCallback(request, sCallback);
		} catch (RuntimeException e) {
			Log.w(TAG, "could not watch Wi-Fi networks", e);
		}
	}

	/**
	 * Find a connected Wi-Fi network and make it the process default.
	 * A Wi-Fi network with no internet still matches: we ask for the Wi-Fi
	 * transport, not for NET_CAPABILITY_INTERNET.
	 */
	private static synchronized void bindWifi() {
		if (sManager == null)
			return;

		Network wifi = null;
		for (Network network : sManager.getAllNetworks()) {
			NetworkCapabilities caps = sManager.getNetworkCapabilities(network);
			if (caps != null && caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) {
				wifi = network;
				break;
			}
		}

		if (wifi == null) {
			Log.i(TAG, "no Wi-Fi yet; game will stay on the last local network");
			return;
		}

		if (wifi.equals(sBound))
			return;

		boolean ok;
		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
			ok = sManager.bindProcessToNetwork(wifi);
		} else {
			// setProcessDefaultNetwork() is the API 21/22 form.
			ok = ConnectivityManager.setProcessDefaultNetwork(wifi);
		}

		if (ok) {
			sBound = wifi;
			Log.i(TAG, "game traffic bound to the home Wi-Fi");
		} else {
			Log.w(TAG, "could not bind game traffic to Wi-Fi");
		}
	}
}
