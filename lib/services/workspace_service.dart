import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/workspace_info.dart';

class WorkspaceService {
  static const _workspacesPref = 'workspaces';
  static const _lastWorkspacePref = 'last_workspace';

  Future<List<WorkspaceInfo>> getWorkspaces() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_workspacesPref);
    if (json == null) return [];
    final list = jsonDecode(json) as List<dynamic>;
    return list
        .map((e) => WorkspaceInfo.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> addWorkspace(WorkspaceInfo workspace) async {
    final workspaces = await getWorkspaces();
    workspaces.add(workspace);
    await _save(workspaces);
  }

  Future<void> removeWorkspace(int index) async {
    final workspaces = await getWorkspaces();
    workspaces.removeAt(index);
    await _save(workspaces);
  }

  Future<void> _save(List<WorkspaceInfo> workspaces) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _workspacesPref,
      jsonEncode(workspaces.map((e) => e.toJson()).toList()),
    );
  }

  Future<String?> getLastWorkspaceName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastWorkspacePref);
  }

  Future<void> setLastWorkspaceName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastWorkspacePref, name);
  }
}
