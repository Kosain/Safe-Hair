import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Use for AppBar/back button: pop if there is a stack, otherwise go to [fallbackRoute].
void backOrGo(BuildContext context, String fallbackRoute) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go(fallbackRoute);
  }
}
