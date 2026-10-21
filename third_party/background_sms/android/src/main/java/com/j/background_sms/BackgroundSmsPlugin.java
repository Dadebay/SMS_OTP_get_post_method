package com.j.background_sms;

import android.app.PendingIntent;
import android.Manifest;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.os.Build;
import android.provider.Settings;
import android.telephony.SmsManager;
import android.telephony.SubscriptionInfo;
import android.telephony.SubscriptionManager;
import android.telephony.TelephonyManager;

import androidx.annotation.NonNull;

import java.util.UUID;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;

/** BackgroundSmsPlugin */
public class BackgroundSmsPlugin implements FlutterPlugin, MethodCallHandler {
  /// The MethodChannel that will the communication between Flutter and native Android
  ///
  /// This local reference serves to register the plugin with the Flutter Engine and unregister it
  /// when the Flutter Engine is detached from the Activity
  private MethodChannel channel;
  private Context context;

  @Override
  public void onAttachedToEngine(@NonNull FlutterPluginBinding flutterPluginBinding) {
    context = flutterPluginBinding.getApplicationContext();
    channel = new MethodChannel(flutterPluginBinding.getFlutterEngine().getDartExecutor(), "background_sms");
    channel.setMethodCallHandler(this);
  }


  @Override
  public void onMethodCall(@NonNull MethodCall call, @NonNull Result result) {
    if (call.method.equals("sendSms")) {
      String num = call.argument("phone");
      String msg = call.argument("msg");
      Integer simSlot = call.argument("simSlot");
      sendSMS(num, msg, simSlot, result);
    } else if (call.method.equals("getSubscriptions")) {
      getSubscriptions(result);
    } else if (call.method.equals("sendSmsDetailed")) {
      sendSmsDetailed(call, result);
    }else if(call.method.equals("isSupportMultiSim")) {
      isSupportCustomSim(result);
    } else{
      result.notImplemented();
    }
  }

  private void getSubscriptions(Result result) {
    if (context.checkSelfPermission(Manifest.permission.READ_PHONE_STATE) != PackageManager.PERMISSION_GRANTED) {
      result.error("PERMISSION_DENIED", "Phone permission required", null);
      return;
    }
    SubscriptionManager manager = (SubscriptionManager) context.getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE);
    List<SubscriptionInfo> active = manager == null ? null : manager.getActiveSubscriptionInfoList();
    List<Map<String, Object>> options = new ArrayList<>();
    if (active != null) for (SubscriptionInfo info : active) {
      Map<String, Object> option = new HashMap<>();
      option.put("id", info.getSubscriptionId());
      option.put("slot", info.getSimSlotIndex());
      option.put("name", info.getDisplayName().toString());
      options.add(option);
    }
    result.success(options);
  }

  private void sendSmsDetailed(MethodCall call, Result result) {
    if (context.checkSelfPermission(Manifest.permission.SEND_SMS) != PackageManager.PERMISSION_GRANTED) {
      result.error("PERMISSION_DENIED", "SMS permission required", null);
      return;
    }
    Integer subscriptionId = call.argument("subscriptionId");
    if (subscriptionId == null) {
      result.error("NO_SIM", "No subscription selected", null);
      return;
    }
    if (context.checkSelfPermission(Manifest.permission.READ_PHONE_STATE) != PackageManager.PERMISSION_GRANTED) {
      result.error("PERMISSION_DENIED", "Phone permission required", null);
      return;
    }
    SubscriptionManager manager = (SubscriptionManager) context.getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE);
    List<SubscriptionInfo> active = manager == null ? null : manager.getActiveSubscriptionInfoList();
    boolean found = false;
    if (active != null) for (SubscriptionInfo info : active) {
      if (info.getSubscriptionId() == subscriptionId) { found = true; break; }
    }
    if (!found) {
      result.error("NO_SIM", "Selected subscription is unavailable", null);
      return;
    }
    if (Settings.Global.getInt(context.getContentResolver(), Settings.Global.AIRPLANE_MODE_ON, 0) != 0) {
      result.error("RADIO_OFF", "Airplane mode", null);
      return;
    }
    try {
      SmsManager smsManager = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S
          ? context.getSystemService(SmsManager.class).createForSubscriptionId(subscriptionId)
          : SmsManager.getSmsManagerForSubscriptionId(subscriptionId);
      smsManager.sendTextMessage(
          call.argument("phone"), null, call.argument("msg"), null, null);
      result.success(null);
    } catch (SecurityException ex) {
      result.error("PERMISSION_DENIED", "SMS permission denied", null);
    } catch (IllegalArgumentException ex) {
      result.error("INVALID_NUMBER", "Invalid recipient", null);
    } catch (Exception ex) {
      result.error("SEND_FAILED", "SMS not accepted", null);
    }
  }

  private void isSupportCustomSim(Result result){
    if(Build.VERSION.SDK_INT >= Build.VERSION_CODES.O){
      result.success(true);
    }else{
      result.success(false);
    }
  }

  private void sendSMS(String num, String msg, Integer simSlot,Result result) {
    try {
      SmsManager smsManager;
      if (simSlot == null) {
        smsManager = SmsManager.getDefault();
      } else {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
          smsManager = SmsManager.getSmsManagerForSubscriptionId(simSlot);
        } else {
          smsManager = SmsManager.getDefault();
        }
      }
      smsManager.sendTextMessage(num, null, msg, null, null);
      result.success("Sent");
    } catch (Exception ex) {
      ex.printStackTrace();
      result.error("Failed", "Sms Not Sent", "");
    }
  }

  @Override
  public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
    channel.setMethodCallHandler(null);
    context = null;
  }
}
