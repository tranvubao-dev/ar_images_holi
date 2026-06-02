import 'dart:io';
import 'package:ar_images_holi/ar_images_holi.dart';
import 'package:ar_quido_example/model.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Permission.camera.request();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  List<String> cachedImagePaths = [];
  List<ARItem> arItems = [];

  @override
  void initState() {
    super.initState();
    loadConfig();
  }

  Future<void> loadConfig() async {
    try {
      final response = await Dio().get<List<dynamic>>(
        'https://s3.holitech.cloud/travelqar/config.json',
      );

      final data = response.data!;

      arItems = data
          .map(
            (e) => ARItem.fromJson(e as Map<String, dynamic>),
          )
          .toList();

      await downloadAndCacheImages();
    } catch (e) {
      debugPrint('Error loading config: $e');
    }
  }

  Future<void> downloadAndCacheImages() async {
    final directory = await getApplicationDocumentsDirectory();
    final paths = <String>[];
    for (final item in arItems) {
      try {
        final url = item.image;
        final fileName = url.split('/').last;
        final filePath = '${directory.path}/$fileName';
        final file = File(filePath);
        print("DOWNLOAD URL: $url");
        if (!file.existsSync()) {
          print("DOWNLOAD URL: $url");
          await Dio().download(
            url,
            filePath,
          );
        }
        paths.add(filePath);
      } catch (e) {
        debugPrint('Error downloading image: $e');
      }
    }

    if (mounted) {
      setState(() {
        cachedImagePaths = paths;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text(
            'AR Quido Example',
          ),
        ),
        body: cachedImagePaths.isEmpty
            ? const Center(
                child: CircularProgressIndicator(),
              )
            : Builder(
                builder: (context) {
                  return Stack(
                    children: [
                      ARQuidoView(
                        referenceImageNames: arItems
                            .map(
                              (e) => e.image.split('/').last,
                            )
                            .toList(),
                        referenceImageUrl: cachedImagePaths,
                        server: 'https://s3.holitech.cloud/travelqar/mp4/',
                      ),
                    ],
                  );
                },
              ),
      ),
    );
  }
}
