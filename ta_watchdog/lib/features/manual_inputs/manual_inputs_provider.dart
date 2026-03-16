import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_client.dart';
import '../../models/manual_input.dart';

final manualInputsProvider = FutureProvider.autoDispose<List<ManualInput>>((ref) async {
  final dio = ref.watch(dioProvider);
  final response = await dio.get('/api/manual_inputs/');
  final List<dynamic> data = (response.data as List?) ?? [];
  final items = data.map((json) => ManualInput.fromJson(json)).toList();
  items.sort((a, b) => a.keyName.compareTo(b.keyName));
  return items;
});

final manualInputsServiceProvider = Provider<ManualInputsService>((ref) {
  return ManualInputsService(ref);
});

class ManualInputsService {
  final Ref ref;

  ManualInputsService(this.ref);

  Future<void> saveInput(ManualInput input) async {
    final dio = ref.read(dioProvider);
    await dio.post(
      '/api/manual_inputs/',
      data: input.toJson(),
    );
    // Refresh the list after save
    ref.invalidate(manualInputsProvider);
  }

  Future<void> deleteInput(int id) async {
    final dio = ref.read(dioProvider);
    await dio.delete('/api/manual_inputs/$id');
    // Refresh the list after delete
    ref.invalidate(manualInputsProvider);
  }
}
