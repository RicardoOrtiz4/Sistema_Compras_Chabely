import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod/legacy.dart';

import 'package:sistema_compras/core/constants.dart';
import 'package:sistema_compras/features/auth/domain/app_user.dart';
import 'package:sistema_compras/features/purchase_packets/data/purchase_packets_repository.dart';
import 'package:sistema_compras/features/purchase_packets/domain/purchase_packet_domain.dart';

class CreatePacketFromReadyOrders {
  const CreatePacketFromReadyOrders(this._repository);

  final PurchasePacketsRepository _repository;

  Future<PurchasePacket> call({
    required AppUser actor,
    required String supplierName,
    required num totalAmount,
    required MoneyCurrency amountCurrency,
    required List<String> evidenceUrls,
    required List<String> itemRefIds,
  }) {
    return _repository.createPacketFromReadyOrders(
      actor: actor,
      supplierName: supplierName,
      totalAmount: totalAmount,
      amountCurrency: amountCurrency,
      evidenceUrls: evidenceUrls,
      itemRefIds: itemRefIds,
    );
  }
}

class SubmitPacketForExecutiveApproval {
  const SubmitPacketForExecutiveApproval(this._repository);

  final PurchasePacketsRepository _repository;

  Future<PurchasePacket> call({
    required AppUser actor,
    required String packetId,
    required int expectedVersion,
  }) {
    return _repository.submitPacketForExecutiveApproval(
      actor: actor,
      packetId: packetId,
      expectedVersion: expectedVersion,
    );
  }
}

class CreateAndSubmitPacketFromReadyOrders {
  const CreateAndSubmitPacketFromReadyOrders(this._repository);

  final PurchasePacketsRepository _repository;

  Future<PurchasePacket> call({
    required AppUser actor,
    required String supplierName,
    required num totalAmount,
    required MoneyCurrency amountCurrency,
    required List<String> evidenceUrls,
    required List<String> itemRefIds,
  }) {
    return _repository.createAndSubmitPacketFromReadyOrders(
      actor: actor,
      supplierName: supplierName,
      totalAmount: totalAmount,
      amountCurrency: amountCurrency,
      evidenceUrls: evidenceUrls,
      itemRefIds: itemRefIds,
    );
  }
}

class ApprovePacket {
  const ApprovePacket(this._repository);

  final PurchasePacketsRepository _repository;

  Future<PurchasePacket> call({
    required AppUser actor,
    required String packetId,
    required int expectedVersion,
    String? reason,
  }) {
    return _repository.approvePacket(
      actor: actor,
      packetId: packetId,
      expectedVersion: expectedVersion,
      reason: reason,
    );
  }
}

class ReturnPacketForRework {
  const ReturnPacketForRework(this._repository);

  final PurchasePacketsRepository _repository;

  Future<PurchasePacket> call({
    required AppUser actor,
    required String packetId,
    required int expectedVersion,
    required String reason,
  }) {
    return _repository.returnPacketForRework(
      actor: actor,
      packetId: packetId,
      expectedVersion: expectedVersion,
      reason: reason,
    );
  }
}

class ClosePacketItemsAsUnpurchasable {
  const ClosePacketItemsAsUnpurchasable(this._repository);

  final PurchasePacketsRepository _repository;

  Future<PurchasePacket> call({
    required AppUser actor,
    required String packetId,
    required int expectedVersion,
    required List<String> itemRefIds,
    required String reason,
  }) {
    return _repository.closePacketItemsAsUnpurchasable(
      actor: actor,
      packetId: packetId,
      expectedVersion: expectedVersion,
      itemRefIds: itemRefIds,
      reason: reason,
    );
  }
}

class RebuildOrderProjectionFromPackets {
  const RebuildOrderProjectionFromPackets(this._repository);

  final PurchasePacketsRepository _repository;

  Future<RequestOrder> call(String orderId) {
    return _repository.rebuildOrderProjectionFromPackets(orderId);
  }
}

final readyOrdersProvider = StreamProvider<List<RequestOrder>>((ref) {
  return ref.watch(purchasePacketsRepositoryProvider).watchReadyOrders();
});

final packetBundlesProvider = StreamProvider<List<PacketBundle>>((ref) {
  return ref.watch(purchasePacketsRepositoryProvider).watchPackets();
});

final dashboardPacketSubmissionCountProvider = StateProvider<int>((ref) => 0);

final pendingDireccionPacketsCountProvider =
    Provider.autoDispose<AsyncValue<int>>((ref) {
      final packetsAsync = ref.watch(packetBundlesProvider);
      return packetsAsync.whenData(
        (bundles) => bundles
            .where(
              (bundle) =>
                  bundle.packet.status == PurchasePacketStatus.approvalQueue,
            )
            .length,
      );
    });

final createPacketFromReadyOrdersProvider = Provider<CreatePacketFromReadyOrders>((ref) {
  return CreatePacketFromReadyOrders(ref.watch(purchasePacketsRepositoryProvider));
});

final submitPacketForExecutiveApprovalProvider = Provider<SubmitPacketForExecutiveApproval>((ref) {
  return SubmitPacketForExecutiveApproval(ref.watch(purchasePacketsRepositoryProvider));
});

final createAndSubmitPacketFromReadyOrdersProvider =
    Provider<CreateAndSubmitPacketFromReadyOrders>((ref) {
      return CreateAndSubmitPacketFromReadyOrders(
        ref.watch(purchasePacketsRepositoryProvider),
      );
    });

final approvePacketProvider = Provider<ApprovePacket>((ref) {
  return ApprovePacket(ref.watch(purchasePacketsRepositoryProvider));
});

final returnPacketForReworkProvider = Provider<ReturnPacketForRework>((ref) {
  return ReturnPacketForRework(ref.watch(purchasePacketsRepositoryProvider));
});

final closePacketItemsAsUnpurchasableProvider = Provider<ClosePacketItemsAsUnpurchasable>((ref) {
  return ClosePacketItemsAsUnpurchasable(ref.watch(purchasePacketsRepositoryProvider));
});

final rebuildOrderProjectionFromPacketsProvider = Provider<RebuildOrderProjectionFromPackets>((ref) {
  return RebuildOrderProjectionFromPackets(ref.watch(purchasePacketsRepositoryProvider));
});
