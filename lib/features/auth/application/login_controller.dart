import 'package:riverpod/riverpod.dart';
import 'package:riverpod/legacy.dart';

import 'package:sistema_compras/core/app_auth.dart';
import 'package:sistema_compras/core/company_branding.dart';
import 'package:sistema_compras/core/error_reporter.dart';
import 'package:sistema_compras/core/login_identity.dart';
import 'package:sistema_compras/features/auth/data/auth_repository.dart';

class LoginState {
  const LoginState({this.isLoading = false, this.error});

  final bool isLoading;
  final Object? error;

  LoginState copyWith({bool? isLoading, Object? error, bool clearError = false}) {
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
      _ref.read(brandingVisibilityLockProvider.notifier).state = true;
      _ref.read(currentCompanyProvider.notifier).prepareForLoginEmail(email);
      final resolution = resolveLoginEmail(email);
      final user = await _signInWithCandidates(
        resolution.authEmailCandidates,
        password,
      );
      await _authRepository.ensureUserDocument(user);
      await _ref
          .read(currentCompanyProvider.notifier)
          .selectForAuthenticatedUser(
            requestedEmail: email,
            authenticatedEmail: user.email ?? resolution.authEmail,
          );
      await saveLastLoginEmail(
        resolution.requestedEmail,
        authenticatedEmail: user.email ?? resolution.authEmail,
      );
      _ref.invalidate(lastLoginEmailProvider);
      state = state.copyWith(isLoading: false, clearError: true);
    } catch (error, stack) {
      _ref.read(currentCompanyProvider.notifier).clearPendingLoginSelection();
      _ref.read(brandingVisibilityLockProvider.notifier).state = false;
      logError(error, stack, context: 'LoginController.signIn');
      state = state.copyWith(isLoading: false, error: error);
    }
  }

  Future<AppAuthUser> _signInWithCandidates(
    List<String> emails,
    String password,
  ) async {
    Object? firstError;
    StackTrace? firstStack;
    for (final authEmail in emails) {
      try {
        return await _authRepository.signIn(
          email: authEmail,
          password: password,
        );
      } catch (error, stack) {
        firstError ??= error;
        firstStack ??= stack;
      }
    }
    Error.throwWithStackTrace(firstError!, firstStack ?? StackTrace.current);
  }
}

final loginControllerProvider =
    StateNotifierProvider<LoginController, LoginState>((ref) {
  final authRepository = ref.watch(authRepositoryProvider);
  return LoginController(authRepository, ref);
});




