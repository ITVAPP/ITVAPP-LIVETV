// Flutter imports:
import 'package:flutter/material.dart';

///Menu item data used in overflow menu (3 dots).
class IAppPlayerOverflowMenuItem {
  ///Icon of menu item
  final IconData icon;

  ///Title of menu item
  final String title;

  ///Callback when item is clicked
  final Function() onClicked;

  IAppPlayerOverflowMenuItem(this.icon, this.title, this.onClicked);
}
