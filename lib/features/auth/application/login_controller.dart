import 'package:riverpod/riverpod.dart';
import 'package:riverpod/legacy.dart';

import 'package:sistema_compras/core/providers.dart';
import 'package:sistema_compras/features/auth/data/auth_repository.dart';

class LoginState {
  const LoginState({this.isLoading = false, this.error});

  final bool isLoading;
  final String? error;

  LoginState copyWith({bool? isLoading, String? error, bool clearError = false}) {
    return LoginState(
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class LoginController extends StateNotifier<LoginState> {
  LoginController(this._authRepository, this._ref) : super(const LoginState());

  final AuthRepository _authRepository;
  final Ref _ref;

  Future<void> signIn(String email, String password) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _authRepository.signIn(email: email, password: password);
      final user = _ref.read(firebaseAuthProvider).currentUser;
      if (user != null) {
        await _authRepository.ensureUserDocument(user);
      }
      state = state.copyWith(isLoading: false, clearError: true);
    } on Exception catch (error) {
      state = state.copyWith(isLoading: false, error: error.toString());
    }
  }
}

final loginControllerProvider =
    StateNotifierProvider<LoginController, LoginState>((ref) {
  final authRepository = ref.watch(authRepositoryProvider);
  return LoginController(authRepository, ref);
});




