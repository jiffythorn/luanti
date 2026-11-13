/*
Kid Town phone client
Copyright (C) 2026 Kid Town contributors

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU Lesser General Public License as published by
the Free Software Foundation; either version 2.1 of the License, or
(at your option) any later version.
*/

package net.minetest.minetest;

import android.app.Activity;
import android.content.ActivityNotFoundException;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.content.pm.Signature;
import android.content.pm.SigningInfo;
import android.net.Uri;
import android.os.Build;
import android.util.Log;
import android.widget.Toast;

import androidx.appcompat.app.AlertDialog;
import androidx.core.content.FileProvider;

import org.json.JSONObject;

import java.io.BufferedInputStream;
import java.io.BufferedReader;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.FileReader;
import java.io.IOException;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.InetAddress;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.Arrays;
import java.util.Locale;

/**
 * Checks the town PC's LAN APK manifest and hands a verified update to the
 * Android package installer.
 *
 * The app cannot install silently: Android always asks the person to confirm
 * an APK update. This class only does the safe part around that confirmation:
 * use the address already saved by Find town, require a local address, verify
 * the manifest and SHA-256, verify the downloaded APK is the same package and
 * signing certificate, then open the system installer.
 */
final class PhoneUpdater {
	private static final String TAG = "KidTownUpdate";
	static final int[] UPDATE_PORTS = {
			8791, 8792, 8793, 8794, 8795, 8796, 8797, 8798, 8799, 8800
	};
	private static final String MANIFEST = "/update.json";
	private static final long MAX_MANIFEST_BYTES = 64 * 1024;
	private static final long MAX_APK_BYTES = 200L * 1024 * 1024;

	private static final class Update {
		final String host;
		final int port;
		final int versionCode;
		final String versionName;
		final String apkPath;
		final String sha256;
		final long size;

		Update(String host, int port, int versionCode, String versionName,
				String apkPath, String sha256, long size) {
			this.host = host;
			this.port = port;
			this.versionCode = versionCode;
			this.versionName = versionName;
			this.apkPath = apkPath;
			this.sha256 = sha256;
			this.size = size;
		}
	}

	private PhoneUpdater() {
	}

	/** Check in the background, then either prompt or continue startup. */
	static void check(final Activity activity, final Runnable proceed) {
		final String host = savedServerHost(activity);
		if (host == null) {
			proceed.run();
			return;
		}

		new Thread(() -> {
			Update update = null;
			try {
				update = findUpdate(host);
			} catch (Exception e) {
				Log.i(TAG, "update check unavailable: " + e.getMessage());
			}
			final Update found = update;
			activity.runOnUiThread(() -> {
				if (activity.isFinishing() || activity.isDestroyed()) {
					return;
				}
				if (found == null) {
					proceed.run();
					return;
				}
				prompt(activity, found, proceed);
			});
		}, "KidTownUpdateCheck").start();
	}

	static String savedServerHost(Context context) {
		File dir = Utils.getUserDataDirectory(context);
		for (String name : new String[] {"minetest.conf", "luanti.conf"}) {
			String value = readSetting(new File(dir, name), "address");
			if (value != null && !value.isEmpty() && isLocalAddress(value))
				return value;
		}
		return null;
	}

	private static String readSetting(File file, String key) {
		if (!file.isFile())
			return null;
		try (BufferedReader reader = new BufferedReader(new FileReader(file))) {
			String line;
			while ((line = reader.readLine()) != null) {
				int eq = line.indexOf('=');
				if (eq < 0)
					continue;
				String name = line.substring(0, eq).trim();
				if (!name.equalsIgnoreCase(key))
					continue;
				String value = line.substring(eq + 1).trim();
				if (value.startsWith("\"") && value.endsWith("\"")
						&& value.length() >= 2)
					value = value.substring(1, value.length() - 1);
				return value;
			}
		} catch (IOException e) {
			Log.i(TAG, "could not read " + file.getName() + ": " + e.getMessage());
		}
		return null;
	}

	static boolean isLocalAddress(String host) {
		try {
			InetAddress address = InetAddress.getByName(host);
			return address.isSiteLocalAddress() || address.isLoopbackAddress()
					|| address.isLinkLocalAddress();
		} catch (Exception e) {
			return false;
		}
	}

	private static Update findUpdate(String host) {
		for (int port : UPDATE_PORTS) {
			HttpURLConnection connection = null;
			try {
				URL url = new URL("http", host, port, MANIFEST);
				connection = (HttpURLConnection) url.openConnection();
				connection.setConnectTimeout(450);
				connection.setReadTimeout(1500);
				connection.setUseCaches(false);
				connection.setInstanceFollowRedirects(false);
				if (connection.getResponseCode() != 200)
					continue;
				String body = readLimited(connection.getInputStream(),
						MAX_MANIFEST_BYTES);
				Update update = parseManifest(host, port, body);
				if (update != null)
					return update;
			} catch (Exception e) {
				Log.i(TAG, "no update manifest on port " + port + ": "
						+ e.getMessage());
			} finally {
				if (connection != null)
					connection.disconnect();
			}
		}
		return null;
	}

	private static Update parseManifest(String host, int port, String body)
			throws Exception {
		JSONObject json = new JSONObject(body);
		int versionCode = json.optInt("versionCode", -1);
		String versionName = json.optString("versionName", "").trim();
		String apkPath = json.optString("apk", "").trim();
		String sha256 = json.optString("sha256", "").trim()
				.toLowerCase(Locale.ROOT);
		long size = json.optLong("size", -1);

		if (versionCode <= BuildConfig.VERSION_CODE)
			return null;
		if (versionName.isEmpty())
			versionName = String.valueOf(versionCode);
		if (apkPath.isEmpty() || !apkPath.startsWith("/")
				|| !apkPath.endsWith(".apk") || apkPath.contains(".."))
			return null;
		if (!sha256.matches("[0-9a-f]{64}"))
			return null;
		if (size <= 0 || size > MAX_APK_BYTES)
			return null;
		return new Update(host, port, versionCode, versionName, apkPath,
				sha256, size);
	}

	private static String readLimited(InputStream input, long max)
			throws IOException {
		try (InputStream in = new BufferedInputStream(input);
				ByteArrayOutputStream out = new ByteArrayOutputStream()) {
			byte[] buffer = new byte[4096];
			long total = 0;
			int count;
			while ((count = in.read(buffer)) != -1) {
				total += count;
				if (total > max)
					throw new IOException("response too large");
				out.write(buffer, 0, count);
			}
			return out.toString(StandardCharsets.UTF_8.name());
		}
	}

	private static void prompt(final Activity activity, final Update update,
			final Runnable proceed) {
		String message = "KidTown " + update.versionName
				+ " is available from the town PC."
				+ "\n\nAndroid will ask you to confirm the install.";
		new AlertDialog.Builder(activity)
				.setTitle("Update KidTown?")
				.setMessage(message)
				.setPositiveButton("Update", (dialog, which) ->
						downloadAndInstall(activity, update, proceed))
				.setNegativeButton("Later", (dialog, which) -> proceed.run())
				.setCancelable(false)
				.show();
	}

	private static void downloadAndInstall(final Activity activity,
			final Update update, final Runnable proceed) {
		Toast.makeText(activity, "Downloading KidTown update...",
				Toast.LENGTH_SHORT).show();
		new Thread(() -> {
			File apk = null;
			String error = null;
			try {
				apk = downloadApk(activity, update);
			} catch (Exception e) {
				error = e.getMessage();
				Log.w(TAG, "update download failed", e);
			}
			final File downloaded = apk;
			final String failure = error;
			activity.runOnUiThread(() -> {
				if (activity.isFinishing() || activity.isDestroyed())
					return;
				if (downloaded == null) {
					Toast.makeText(activity,
							"Update download failed: " + failure,
							Toast.LENGTH_LONG).show();
					proceed.run();
					return;
				}
				install(activity, downloaded, proceed);
			});
		}, "KidTownUpdateDownload").start();
	}

	private static File downloadApk(Activity activity, Update update)
			throws Exception {
		File dir = new File(activity.getCacheDir(), "updates");
		if (!dir.isDirectory() && !dir.mkdirs())
			throw new IOException("cannot create update folder");
		File apk = new File(dir, "KidTown-phone.apk");
		if (apk.exists() && !apk.delete())
			throw new IOException("cannot replace old update file");

		URL url = new URL("http", update.host, update.port, update.apkPath);
		HttpURLConnection connection = (HttpURLConnection) url.openConnection();
		connection.setConnectTimeout(1500);
		connection.setReadTimeout(15000);
		connection.setUseCaches(false);
		connection.setInstanceFollowRedirects(false);
		try {
			if (connection.getResponseCode() != 200)
				throw new IOException("server returned "
						+ connection.getResponseCode());
			MessageDigest digest = MessageDigest.getInstance("SHA-256");
			long total = 0;
			try (InputStream in = new BufferedInputStream(
					connection.getInputStream());
					FileOutputStream out = new FileOutputStream(apk)) {
				byte[] buffer = new byte[64 * 1024];
				int count;
				while ((count = in.read(buffer)) != -1) {
					out.write(buffer, 0, count);
					digest.update(buffer, 0, count);
					total += count;
					if (total > MAX_APK_BYTES)
						throw new IOException("APK is too large");
				}
			}
			if (total != update.size)
				throw new IOException("APK size did not match the manifest");
			String actual = hex(digest.digest());
			if (!actual.equals(update.sha256))
				throw new IOException("APK checksum did not match");
			return apk;
		} catch (Exception e) {
			apk.delete();
			throw e;
		} finally {
			connection.disconnect();
		}
	}

	private static String hex(byte[] bytes) {
		StringBuilder out = new StringBuilder(bytes.length * 2);
		for (byte value : bytes)
			out.append(String.format(Locale.ROOT, "%02x", value & 0xff));
		return out.toString();
	}

	private static void install(Activity activity, File apk,
			Runnable proceed) {
		try {
			if (!apkMatchesInstalled(activity, apk)) {
				Toast.makeText(activity,
						"Update is not a valid KidTown build.",
						Toast.LENGTH_LONG).show();
				proceed.run();
				return;
			}
		} catch (Exception e) {
			Log.w(TAG, "could not verify update APK", e);
			Toast.makeText(activity, "Could not verify the update.",
					Toast.LENGTH_LONG).show();
			proceed.run();
			return;
		}

		// Android's package installer owns the unknown-sources permission
		// prompt. Do not gate the handoff here: older releases handle the
		// prompt differently, and a pre-check made the app sit on its loading
		// screen after returning from Settings.
		Uri uri = FileProvider.getUriForFile(activity,
				"net.minetest.minetest.fileprovider", apk);
		Intent install = new Intent(Intent.ACTION_VIEW);
		install.setDataAndType(uri,
				"application/vnd.android.package-archive");
		install.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
		install.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
		try {
			activity.startActivity(install);
		} catch (ActivityNotFoundException e) {
			Toast.makeText(activity, "No Android installer found.",
					Toast.LENGTH_LONG).show();
			proceed.run();
		}
	}

	private static boolean apkMatchesInstalled(Context context, File apk)
			throws Exception {
		PackageManager pm = context.getPackageManager();
		int flags = Build.VERSION.SDK_INT >= Build.VERSION_CODES.P
				? PackageManager.GET_SIGNING_CERTIFICATES
				: PackageManager.GET_SIGNATURES;
		PackageInfo archive = pm.getPackageArchiveInfo(apk.getAbsolutePath(),
				flags);
		if (archive == null
				|| !context.getPackageName().equals(archive.packageName)
				|| archive.versionCode <= BuildConfig.VERSION_CODE)
			return false;
		PackageInfo installed = pm.getPackageInfo(context.getPackageName(),
				flags);
		Signature[] archiveSignatures = signatures(archive);
		Signature[] installedSignatures = signatures(installed);
		return archiveSignatures.length > 0
				&& installedSignatures.length > 0
				&& Arrays.equals(archiveSignatures[0].toByteArray(),
						installedSignatures[0].toByteArray());
	}

	private static Signature[] signatures(PackageInfo info) {
		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
			SigningInfo signing = info.signingInfo;
			if (signing == null)
				return new Signature[0];
			Signature[] signers = signing.getApkContentsSigners();
			return signers == null ? new Signature[0] : signers;
		}
		return info.signatures == null ? new Signature[0] : info.signatures;
	}
}
