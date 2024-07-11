import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tang_iap/config/tang_iap_config.dart';
import 'package:tang_iap/iap/iap_model.dart';
import 'package:tang_iap/iap/iap_util.dart';
import 'package:tang_util/util/util.dart';

/// * 大致流程 *
/// 1、初始化、加载Products identifier List
/// 2、业务发起支付，检查是否当前正在处理，检查Products identifier List加载状态
/// 3、处理付款回调，过程：
///   a、cancel/error的直接complete，并发出signal
///   b、purchased的校验付款时间，校验失败直接return，并complete
///   c、purchased的校验成功，调用当前流程中给定的IapPurchaseValidator实例
///   d、IapPurchaseValidator实例校验结果回调后，IAPHelper处理校验结果和缓存状态
/// 4、发出处理结果signal

class IAPHelper {
  factory IAPHelper() => _getInstance();
  static IAPHelper _getInstance() { return _instance; }
  static IAPHelper get shared => _getInstance();
  static final IAPHelper _instance = IAPHelper._internal();
  IAPHelper._internal();
  late IAPConfig _config;

  final StreamController<IapErrorResult> _errorCtr =
    StreamController.broadcast();
  final StreamController<List<PurchaseDetails>> _detailsCtr =
    StreamController.broadcast();
  final StreamController<List<ProductDetails>> _productsCtr =
    StreamController.broadcast();

  final unverifiedPurchasesCacheKey = 'UnverifiedPurchasesCacheKey';
  final List<ProductDetails> _loadedProducts = [];
  StreamSubscription<List<PurchaseDetails>>? _sub;
  Set<String>? _currentProductIds;
  ProductDetails? _processingProduct;
  IapPurchaseValidator? _purchaseValidator;

  /// Processing the purchase-restore for now.
  bool _isProcessingRestore = false;
}

// Define

extension Define on IAPHelper {}

enum IapError { notLoad, loadFailed, processing, canceled, restoreEmpty }

class IapErrorResult {
  final IapError error;
  final dynamic detail;
  IapErrorResult(this.error, {this.detail});
}

abstract class IapPurchaseValidator {

  /// Verifying the paid purchase and return the result.
  Future<bool> verifyPurchase(List<PurchaseDetails> purchaseDetails, {
    ProductDetails? processingProduct,
  });

  /// The verification all completed.
  completed();
}

// Getter

extension Getters on IAPHelper {
  IAPConfig get config => _config;
  Future<bool> get isAvailable => InAppPurchase.instance.isAvailable();
  Stream<IapErrorResult> get errorStream => _errorCtr.stream;
  Stream<List<PurchaseDetails>> get detailsStream => _detailsCtr.stream;
  Stream<List<ProductDetails>> get productsStream => _productsCtr.stream;
  List<ProductDetails> get products => _loadedProducts;
}

extension _GettersThatPrivate on IAPHelper {

  /// Processing payment.
  bool get _isProcessingProduct => _processingProduct != null;
  /// Has unverified purchase at least one.
  Future<bool> _hasUnverifiedPurchase(String productId) async {
    return (await _unverifiedPurchase(productId)) != null;
  }
  /// Unverified purchase.
  Future<IAPPurchaseNecessaryInfoModel?> _unverifiedPurchase(
      String productId) async {
    final sp = await SharedPreferences.getInstance();
    final json = (sp.getString(unverifiedPurchasesCacheKey) ?? '[]').toJson();
    if (json is! List) return Future.value(null);
    List<IAPPurchaseNecessaryInfoModel> models = json.map((e) =>
        IAPPurchaseNecessaryInfoModel.fromJson(e)).toList();
    final index = models.indexWhere((e) => e.productID == productId);
    final contains = index != -1;
    return Future.value(contains ? models[index] : null);
  }
}

// Request

extension _Request on IAPHelper {

  _loadProducts({Set<String>? identifiers}) async {
    if (_config.defaultProductIdentifiers.isEmpty) return;

    Set<String> ids = identifiers ?? _config.defaultProductIdentifiers;
    _currentProductIds = ids;
    final response = await InAppPurchase.instance.queryProductDetails(ids);

    if (response.notFoundIDs.isNotEmpty) {
      final error = 'Failed to load the PIDs: ${response.notFoundIDs}';
      final errorObj = {'error': error, 'detail': response.notFoundIDs};
      if (kDebugMode) print(error);
      _errorCtr.sink.add(IapErrorResult(IapError.loadFailed, detail: errorObj));
      Future.delayed(const Duration(seconds: 5), () => _loadProducts(
        identifiers: identifiers,
      ));
    }

    _loadedProducts.clear();
    _loadedProducts.addAll(response.productDetails);
    _productsCtr.sink.add(_loadedProducts);
  }
}

// Private

extension _Private on IAPHelper {

  _binds() {
    _sub = InAppPurchase.instance.purchaseStream.listen((purchaseList) async {
      _detailsCtr.sink.add(purchaseList);

      /// Canceled or Failed purchases.
      List<PurchaseDetails> errorDetails = purchaseList.where((d) {
        return d.status == PurchaseStatus.error
            || d.status == PurchaseStatus.canceled;
      }).toList();
      _handleCanceledAndFailedPurchaseItems(errorDetails);

      /// Completed purchases.
      List<PurchaseDetails> validAndPaidDetails = purchaseList.where((d) {
        if (d.status != PurchaseStatus.purchased) { return false; }
        int transDateMs = int.parse(d.transactionDate ?? '0');
        bool paidJustNow = (DateTime.now().millisecondsSinceEpoch - transDateMs)
            <= _config.purchasedItemValidMs;
        return paidJustNow || d.pendingCompletePurchase;
      }).toList();
      _handlePaidPurchaseItems(validAndPaidDetails);

      /// Restored purchases.
      List<PurchaseDetails> restoredDetails = purchaseList.where((d) {
        return d.status == PurchaseStatus.restored;
      }).toList();
      if (validAndPaidDetails.isEmpty) {
        _handleRestoredPurchaseItems(restoredDetails);
      }
    }, onDone: () {
      if (kDebugMode) print('IAP stream done.');
    }, onError: (error) {
      if (kDebugMode) print('IAP error: $error');
      _errorCtr.sink.add(error);
    });
  }

  _handleCanceledAndFailedPurchaseItems(List<PurchaseDetails> details) async {
    if (details.isEmpty) return;
    _processingProduct = null;
    _errorCtr.sink.add(IapErrorResult(IapError.canceled, detail: details));
    for (var e in details) {
      await InAppPurchase.instance.completePurchase(e);
    }
  }

  _handlePaidPurchaseItems(List<PurchaseDetails> details) async {
    if (details.isEmpty) return;
    _processingProduct = null;

    final json = jsonEncode(details.map((e) => e.necessaryJsonInfo()).toList());
    final sp = await SharedPreferences.getInstance();
    await sp.setString(unverifiedPurchasesCacheKey, json);
    final verifyResult = await _purchaseValidator?.verifyPurchase(
      details,
      processingProduct: _processingProduct,
    ) ?? false;

    if (!verifyResult) return;
    sp.remove(unverifiedPurchasesCacheKey);
    _purchaseValidator?.completed();
    for (var e in details) {
      await InAppPurchase.instance.completePurchase(e);
    }
  }

  _handleRestoredPurchaseItems(List<PurchaseDetails> details) async {
    if (!_isProcessingRestore) return;
    _isProcessingRestore = false;
    if (details.isEmpty) {
      _errorCtr.sink.add(IapErrorResult(IapError.restoreEmpty));
      return;
    }
    _handlePaidPurchaseItems(details);
  }
}

// Public

extension Public on IAPHelper {

  setup({required IAPConfig config}) async {
    _config = config;
    if (!Platform.isIOS) return;
    _binds();
    _loadProducts();
  }

  reloadProductIdentifier(Set<String> identifiers) {
    if (identifiers.isEmpty) return;
    _loadProducts(identifiers: identifiers);
  }

  dispose() {
    _sub?.cancel();
  }

  restorePurchases() async {
    if (_isProcessingRestore) return;
    _isProcessingRestore = true;
    await InAppPurchase.instance.restorePurchases();
  }
}

extension PublicOfBuy on IAPHelper {

  /// Buying item with productId.
  ///
  /// [productId] Product ID.
  /// [isConsumable] Consumable / NonConsumable.
  /// [purchaseValidator] Implements of IapPurchaseValidator.
  Future<bool> buy(String productId, {
    bool isConsumable = false,
    required IapPurchaseValidator purchaseValidator,
  }) async {
    /// Error - Processing.
    if (_isProcessingProduct) {
      _errorCtr.sink.add(IapErrorResult(
        IapError.processing,
        detail: _processingProduct,
      ));
      return Future.value(false);
    }

    /// Error - Loading.
    if (_loadedProducts.indexWhere((e) => e.id == productId) < 0) {
      _errorCtr.sink.add(IapErrorResult(IapError.notLoad));
      _loadProducts(identifiers: _currentProductIds);
      return Future.value(false);
    }

    /// Error - Unverified.
    _purchaseValidator = purchaseValidator;
    final unverifiedPurchase = await _unverifiedPurchase(productId);
    if (await _hasUnverifiedPurchase(productId)) {
      await _handlePaidPurchaseItems([unverifiedPurchase!.toPurchaseDetails]);
      return Future.value(true);
    }

    /// Pay request.
    ProductDetails d = _loadedProducts.firstWhere((e) => e.id == productId);
    _processingProduct = d;
    final PurchaseParam param = PurchaseParam(productDetails: d);
    try {
      if (isConsumable) {
        return await InAppPurchase.instance.buyConsumable(
          purchaseParam: param,
        );
      }
      return await InAppPurchase.instance.buyNonConsumable(
        purchaseParam: param,
      );
    } catch (e) {
      if (kDebugMode) print('IAP helper error: $e');
      if (e is PlatformException &&
          e.code == 'storekit_duplicate_product_object') {
        _errorCtr.sink.add(IapErrorResult(IapError.processing));
      }
      return Future.value(false);
    }
  }
}