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
import android.content.ContentResolver;
import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.net.Uri;
import android.os.Bundle;
import android.provider.MediaStore;
import android.text.InputType;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.CheckBox;
import android.widget.EditText;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import androidx.core.content.FileProvider;

import org.json.JSONException;
import org.json.JSONObject;

import java.io.BufferedInputStream;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.InetAddress;
import java.net.URL;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;

/**
 * One-photo bridge from the phone to the town PC's ID Department.
 *
 * The app never talks to a cloud service. It sends the compressed frame to the
 * private town address over the home Wi-Fi, then removes every temporary copy
 * it made. A photo chosen from the gallery is copied first; the gallery
 * original is never touched or deleted.
 */
public class PhotoActivity extends Activity {
	private static final int REQUEST_CAMERA = 41;
	private static final int REQUEST_GALLERY = 42;
	private static final String AUTHORITY = "net.minetest.minetest.fileprovider";
	private static final String UPLOAD_DIR = "photo-upload";
	private static final int MAX_LOCAL_BYTES = 12 * 1024 * 1024;
	private static final long MAX_RESPONSE_BYTES = 64 * 1024;

	private EditText nameInput;
	private CheckBox consent;
	private ImageView preview;
	private TextView status;
	private Button takeButton;
	private Button pickButton;
	private Button sendButton;
	private Button cancelButton;
	private File selectedFile;
	private File cameraFile;
	private File uploadFile;
	private boolean busy;

	private final Runnable refreshSend = () -> {
		if (sendButton != null)
			sendButton.setEnabled(!busy && selectedFile != null
					&& consent != null && consent.isChecked());
	};

	@Override
	protected void onCreate(Bundle savedInstanceState) {
		super.onCreate(savedInstanceState);
		cleanOldTemporaryFiles();
		buildUi();
		Intent intent = getIntent();
		if (intent != null && Intent.ACTION_SEND.equals(intent.getAction())
				&& intent.getType() != null
				&& intent.getType().startsWith("image/")) {
			Uri shared = intent.getParcelableExtra(Intent.EXTRA_STREAM);
			if (shared != null)
				receiveSharedPhoto(shared);
		}
	}

	private int dp(int value) {
		return Math.round(getResources().getDisplayMetrics().density * value);
	}

	private void buildUi() {
		ScrollView scroll = new ScrollView(this);
		LinearLayout root = new LinearLayout(this);
		root.setOrientation(LinearLayout.VERTICAL);
		root.setPadding(dp(22), dp(18), dp(22), dp(26));
		scroll.addView(root);

		TextView title = new TextView(this);
		title.setText("Send a photo to the ID Department");
		title.setTextSize(24);
		title.setGravity(Gravity.START);
		root.addView(title);

		TextView help = new TextView(this);
		help.setText("The photo goes only to your town PC over the home Wi-Fi. "
				+ "The town PC makes the ID; this phone deletes its temporary "
				+ "copy after it answers. If the name matches the player's town "
				+ "name, the generated look also becomes their avatar. A photo "
				+ "picked from Gallery is copied first, so the original in "
				+ "Gallery is not deleted.");
		help.setTextSize(16);
		help.setPadding(0, dp(8), 0, dp(12));
		root.addView(help);

		TextView nameLabel = new TextView(this);
		nameLabel.setText("Name for the ID card (and town avatar)");
		nameLabel.setTextSize(16);
		root.addView(nameLabel);

		nameInput = new EditText(this);
		nameInput.setSingleLine(true);
		nameInput.setHint("e.g. Noah");
		nameInput.setInputType(InputType.TYPE_CLASS_TEXT
				| InputType.TYPE_TEXT_FLAG_CAP_WORDS);
		root.addView(nameInput, new LinearLayout.LayoutParams(
				ViewGroup.LayoutParams.MATCH_PARENT,
				ViewGroup.LayoutParams.WRAP_CONTENT));

		consent = new CheckBox(this);
		consent.setText("I am the parent or guardian. I approve this one photo "
				+ "being sent to the town PC for the ID Department.");
		consent.setTextSize(16);
		consent.setPadding(0, dp(12), 0, dp(8));
		consent.setOnCheckedChangeListener((button, checked) -> refreshSend.run());
		root.addView(consent);

		preview = new ImageView(this);
		preview.setAdjustViewBounds(true);
		preview.setScaleType(ImageView.ScaleType.FIT_CENTER);
		preview.setMinimumHeight(dp(180));
		preview.setBackgroundColor(0xffeef2e8);
		root.addView(preview, new LinearLayout.LayoutParams(
				ViewGroup.LayoutParams.MATCH_PARENT, dp(240)));

		LinearLayout photoRow = new LinearLayout(this);
		photoRow.setOrientation(LinearLayout.HORIZONTAL);
		photoRow.setPadding(0, dp(10), 0, 0);
		takeButton = new Button(this);
		takeButton.setText("Take photo");
		takeButton.setOnClickListener(view -> takePhoto());
		pickButton = new Button(this);
		pickButton.setText("Choose photo");
		pickButton.setOnClickListener(view -> choosePhoto());
		photoRow.addView(takeButton, new LinearLayout.LayoutParams(0,
				ViewGroup.LayoutParams.WRAP_CONTENT, 1));
		photoRow.addView(pickButton, new LinearLayout.LayoutParams(0,
				ViewGroup.LayoutParams.WRAP_CONTENT, 1));
		root.addView(photoRow);

		LinearLayout actionRow = new LinearLayout(this);
		actionRow.setOrientation(LinearLayout.HORIZONTAL);
		actionRow.setPadding(0, dp(10), 0, 0);
		sendButton = new Button(this);
		sendButton.setText("Send to town PC");
		sendButton.setEnabled(false);
		sendButton.setOnClickListener(view -> sendToTown());
		cancelButton = new Button(this);
		cancelButton.setText("Cancel");
		cancelButton.setOnClickListener(view -> {
			cleanupTemporaryFiles();
			finish();
		});
		actionRow.addView(sendButton, new LinearLayout.LayoutParams(0,
				ViewGroup.LayoutParams.WRAP_CONTENT, 1));
		actionRow.addView(cancelButton, new LinearLayout.LayoutParams(0,
				ViewGroup.LayoutParams.WRAP_CONTENT, 1));
		root.addView(actionRow);

		status = new TextView(this);
		status.setTextSize(15);
		status.setPadding(0, dp(12), 0, 0);
		status.setText("Choose a photo first.");
		root.addView(status);

		setContentView(scroll);
	}

	private File uploadDir() {
		File dir = new File(getCacheDir(), UPLOAD_DIR);
		if (!dir.isDirectory() && !dir.mkdirs())
			return null;
		return dir;
	}

	private void cleanOldTemporaryFiles() {
		File dir = uploadDir();
		if (dir == null)
			return;
		File[] files = dir.listFiles();
		if (files == null)
			return;
		for (File file : files) {
			if (file.isFile())
				file.delete();
		}
	}

	private void setStatus(String text) {
		if (status != null)
			status.setText(text);
	}

	private void setBusy(boolean value) {
		busy = value;
		if (takeButton != null) takeButton.setEnabled(!value);
		if (pickButton != null) pickButton.setEnabled(!value);
		if (cancelButton != null) cancelButton.setEnabled(!value);
		refreshSend.run();
	}

	private File newTemporaryFile(String prefix, String suffix) throws IOException {
		File dir = uploadDir();
		if (dir == null)
			throw new IOException("cannot make a temporary photo folder");
		return File.createTempFile(prefix, suffix, dir);
	}

	private void takePhoto() {
		if (busy)
			return;
		cleanupTemporaryFiles();
		try {
			cameraFile = newTemporaryFile("camera-", ".jpg");
			Uri output = FileProvider.getUriForFile(this, AUTHORITY, cameraFile);
			Intent intent = new Intent(MediaStore.ACTION_IMAGE_CAPTURE);
			intent.putExtra(MediaStore.EXTRA_OUTPUT, output);
			intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION
					| Intent.FLAG_GRANT_WRITE_URI_PERMISSION);
			intent.setClipData(android.content.ClipData.newRawUri("KidTown photo", output));
			if (intent.resolveActivity(getPackageManager()) == null) {
				setStatus("No camera app is available on this phone.");
				return;
			}
			startActivityForResult(intent, REQUEST_CAMERA);
		} catch (Exception error) {
			cleanupTemporaryFiles();
			setStatus("Could not open the camera: " + error.getMessage());
		}
	}

	private void choosePhoto() {
		if (busy)
			return;
		Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
		intent.addCategory(Intent.CATEGORY_OPENABLE);
		intent.setType("image/*");
		try {
			startActivityForResult(intent, REQUEST_GALLERY);
		} catch (Exception error) {
			setStatus("Could not open the photo picker: " + error.getMessage());
		}
	}

	@Override
	protected void onActivityResult(int requestCode, int resultCode, Intent data) {
		super.onActivityResult(requestCode, resultCode, data);
		if (resultCode != RESULT_OK) {
			cleanupTemporaryFiles();
			setStatus("No photo chosen.");
			return;
		}
		try {
			if (requestCode == REQUEST_CAMERA) {
				if (cameraFile == null || !cameraFile.isFile()
						|| cameraFile.length() == 0)
					throw new IOException("the camera did not save a photo");
				selectedFile = cameraFile;
				cameraFile = null;
			} else if (requestCode == REQUEST_GALLERY) {
				Uri uri = data == null ? null : data.getData();
				if (uri == null)
					throw new IOException("the picker did not return a photo");
				selectedFile = copyFromUri(uri);
			} else {
				return;
			}
			showPreview(selectedFile);
			refreshSend.run();
			setStatus("Photo ready. A grown-up must tick the approval box, "
					+ "then press Send to town PC.");
		} catch (Exception error) {
			cleanupTemporaryFiles();
			setStatus("Could not read that photo: " + error.getMessage());
		}
	}

	private File copyFromUri(Uri uri) throws IOException {
		File copy = newTemporaryFile("picked-", ".img");
		ContentResolver resolver = getContentResolver();
		try (InputStream in = new BufferedInputStream(resolver.openInputStream(uri));
				OutputStream out = new FileOutputStream(copy)) {
			byte[] buffer = new byte[64 * 1024];
			long total = 0;
			int count;
			while ((count = in.read(buffer)) != -1) {
				total += count;
				if (total > MAX_LOCAL_BYTES)
					throw new IOException("that photo is too large");
				out.write(buffer, 0, count);
			}
		} catch (Exception error) {
			copy.delete();
			throw error;
		}
		if (copy.length() == 0) {
			copy.delete();
			throw new IOException("that photo is empty");
		}
		return copy;
	}

	@SuppressWarnings("deprecation")
	private void receiveSharedPhoto(Uri uri) {
		try {
			cleanupTemporaryFiles();
			selectedFile = copyFromUri(uri);
			showPreview(selectedFile);
			refreshSend.run();
			setStatus("Photo received. A grown-up must approve, then press "
					+ "Send to town PC.");
		} catch (Exception error) {
			cleanupTemporaryFiles();
			setStatus("Could not read the shared photo: " + error.getMessage());
		}
	}

	private void showPreview(File file) {
		BitmapFactory.Options bounds = new BitmapFactory.Options();
		bounds.inJustDecodeBounds = true;
		BitmapFactory.decodeFile(file.getAbsolutePath(), bounds);
		int sample = 1;
		int longest = Math.max(bounds.outWidth, bounds.outHeight);
		while (longest / sample > 1600)
			sample *= 2;
		BitmapFactory.Options options = new BitmapFactory.Options();
		options.inSampleSize = sample;
		Bitmap bitmap = BitmapFactory.decodeFile(file.getAbsolutePath(), options);
		if (bitmap != null)
			preview.setImageBitmap(bitmap);
	}

	private File prepareForUpload(File source) throws IOException {
		BitmapFactory.Options bounds = new BitmapFactory.Options();
		bounds.inJustDecodeBounds = true;
		BitmapFactory.decodeFile(source.getAbsolutePath(), bounds);
		if (bounds.outWidth <= 0 || bounds.outHeight <= 0)
			throw new IOException("that file is not a readable photo");
		int sample = 1;
		int longest = Math.max(bounds.outWidth, bounds.outHeight);
		while (longest / sample > 1600)
			sample *= 2;
		BitmapFactory.Options options = new BitmapFactory.Options();
		options.inSampleSize = sample;
		Bitmap bitmap = BitmapFactory.decodeFile(source.getAbsolutePath(), options);
		if (bitmap == null)
			throw new IOException("that file is not a readable photo");
		float scale = Math.min(1f, 1600f / Math.max(bitmap.getWidth(),
				bitmap.getHeight()));
		Bitmap scaled = bitmap;
		if (scale < 1f) {
			scaled = Bitmap.createScaledBitmap(bitmap,
					Math.max(1, Math.round(bitmap.getWidth() * scale)),
					Math.max(1, Math.round(bitmap.getHeight() * scale)), true);
			if (scaled != bitmap)
				bitmap.recycle();
		}
		File output = newTemporaryFile("upload-", ".jpg");
		try (OutputStream out = new FileOutputStream(output)) {
			if (!scaled.compress(Bitmap.CompressFormat.JPEG, 86, out))
				throw new IOException("could not prepare the photo");
		} finally {
			scaled.recycle();
		}
		if (output.length() == 0)
			throw new IOException("could not prepare the photo");
		return output;
	}

	private void sendToTown() {
		if (busy || selectedFile == null)
			return;
		if (consent == null || !consent.isChecked()) {
			setStatus("A grown-up must tick the approval box first.");
			return;
		}
		String name = nameInput == null ? "" : nameInput.getText().toString().trim();
		setBusy(true);
		setStatus("Preparing the photo...");
		try {
			uploadFile = prepareForUpload(selectedFile);
		} catch (Exception error) {
			cleanupTemporaryFiles();
			setBusy(false);
			setStatus("Could not prepare that photo: " + error.getMessage());
			return;
		}
		setStatus("Sending to the town PC...");
		final String chosenName = name;
		new Thread(() -> {
			String message;
			boolean ok = false;
			try {
				String host = PhoneUpdater.savedServerHost(this);
				if (host == null)
					throw new IOException("Choose a town in Join Game first.");
				InetAddress address = InetAddress.getByName(host);
				String ip = address.getHostAddress();
				if (!PhoneUpdater.isLocalAddress(ip))
					throw new IOException("The town PC is not on this home Wi-Fi.");
				message = uploadToTown(ip, chosenName);
				ok = true;
			} catch (Exception error) {
				message = "Could not send the photo: " + error.getMessage()
						+ "\nThe phone copy was deleted.";
			} finally {
				// This is the important promise: no phone copy survives the
				// upload attempt, whether the town PC answered or not.
				cleanupTemporaryFiles();
			}
			final boolean success = ok;
			final String result = message;
			runOnUiThread(() -> {
				setBusy(false);
				setStatus(result);
				if (success) {
					Toast.makeText(this, "ID Department: photo sent",
							Toast.LENGTH_LONG).show();
					finish();
				}
			});
		}, "KidTownPhotoUpload").start();
	}

	private String uploadToTown(String host, String name) throws IOException {
		String encodedName = URLEncoder.encode(name == null ? "" : name,
				StandardCharsets.UTF_8.name());
		byte[] bytes = readFile(uploadFile);
		String lastError = "The town PC did not answer.";
		for (int port : PhoneUpdater.UPDATE_PORTS) {
			HttpURLConnection connection = null;
			try {
				URL url = new URL("http", host, port,
						"/v1/id/photo?name=" + encodedName);
				connection = (HttpURLConnection) url.openConnection();
				connection.setConnectTimeout(4000);
				connection.setReadTimeout(120000);
				connection.setUseCaches(false);
				connection.setInstanceFollowRedirects(false);
				connection.setDoOutput(true);
				connection.setRequestMethod("POST");
				connection.setFixedLengthStreamingMode(bytes.length);
				connection.setRequestProperty("Content-Type", "image/jpeg");
				connection.setRequestProperty("X-KidTown-Parent-Approved", "1");
				connection.setRequestProperty("Accept", "application/json");
				connection.setRequestProperty("Connection", "close");
				try (OutputStream out = connection.getOutputStream()) {
					out.write(bytes);
				}
				int code = connection.getResponseCode();
				String body = readResponse(code >= 400
						? connection.getErrorStream() : connection.getInputStream());
					if (code == 200) {
						JSONObject json;
						try {
							json = new JSONObject(body);
						} catch (JSONException error) {
							lastError = "The town PC sent an unreadable answer.";
							break;
						}
						if (json.optBoolean("ok")) {
						String serial = json.optString("serial", "");
						return "Photo sent. The town PC made the ID"
								+ (serial.isEmpty() ? "." : " " + serial + ".")
								+ "\nThe phone copy was deleted.";
					}
					lastError = json.optString("error", "The town PC refused it.");
					break;
				}
				lastError = body.isEmpty() ? ("Town PC returned " + code)
						: body;
				// A real HTTP answer means we reached the town PC. Do not
				// spray the same photo across the rest of the port range.
				break;
			} catch (IOException error) {
				lastError = error.getMessage();
			} finally {
				if (connection != null)
					connection.disconnect();
			}
		}
		throw new IOException(lastError);
	}

	private static byte[] readFile(File file) throws IOException {
		try (InputStream in = new BufferedInputStream(
				new java.io.FileInputStream(file));
				ByteArrayOutputStream out = new ByteArrayOutputStream()) {
			byte[] buffer = new byte[64 * 1024];
			int count;
			long total = 0;
			while ((count = in.read(buffer)) != -1) {
				total += count;
				if (total > MAX_LOCAL_BYTES)
					throw new IOException("the photo is too large");
				out.write(buffer, 0, count);
			}
			return out.toByteArray();
		}
	}

	private static String readResponse(InputStream input) throws IOException {
		if (input == null)
			return "";
		try (InputStream in = new BufferedInputStream(input);
				ByteArrayOutputStream out = new ByteArrayOutputStream()) {
			byte[] buffer = new byte[4096];
			int count;
			long total = 0;
			while ((count = in.read(buffer)) != -1) {
				total += count;
				if (total > MAX_RESPONSE_BYTES)
					throw new IOException("the town PC sent too much data");
				out.write(buffer, 0, count);
			}
			return out.toString(StandardCharsets.UTF_8.name()).trim();
		}
	}

	private void cleanupTemporaryFiles() {
		if (selectedFile != null) {
			selectedFile.delete();
			selectedFile = null;
		}
		if (cameraFile != null) {
			cameraFile.delete();
			cameraFile = null;
		}
		if (uploadFile != null) {
			uploadFile.delete();
			uploadFile = null;
		}
		cleanOldTemporaryFiles();
	}

	@Override
	protected void onDestroy() {
		cleanupTemporaryFiles();
		super.onDestroy();
	}
}
