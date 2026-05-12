// import 'package:ar_quido/ar_quido.dart';
// import 'package:flutter/material.dart';
// import 'package:permission_handler/permission_handler.dart';

// Future<void> main() async {
//   WidgetsFlutterBinding.ensureInitialized();
//   await Permission.camera.request();
//   runApp(const MyApp());
// }

// class MyApp extends StatefulWidget {
//   const MyApp({super.key});

//   @override
//   State<MyApp> createState() => _MyAppState();
// }

// class _MyAppState extends State<MyApp> {
//   String? _recognizedImage;

//   void _onImageDetected(BuildContext context, String? imageName) {
//     if (imageName != null && _recognizedImage != imageName) {
//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(
//           content: Text('Recognized image: $imageName'),
//           duration: const Duration(milliseconds: 2500),
//         ),
//       );
//     }
//     setState(() {
//       _recognizedImage = imageName;
//     });
//   }

//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       home: Scaffold(
//         appBar: AppBar(
//           title: const Text('Plugin example app'),
//         ),
//         body: Builder(
//           builder: (context) {
//             return Stack(
//               children: [
//                 ARQuidoView(
//                   referenceImageNames: const [
//                     'baotang.jpg',
//                     'flcsafari.jpg',
//                     'hohoankiem.jpg',
//                     'khamphakhoahoc.jpg',
//                     'thapcham.jpg',
//                     'thuydienialy.jpg',
//                   ],
//                   referenceImageUrl: const [
//                     'https://s3.holitech.cloud/travelqar/images/baotang.jpg',
//                     'https://s3.holitech.cloud/travelqar/images/flcsafari.jpg',
//                     'https://s3.holitech.cloud/travelqar/images/hohoankiem.jpg',
//                     'https://s3.holitech.cloud/travelqar/images/khamphakhoahoc.jpg',
//                     'https://s3.holitech.cloud/travelqar/images/thapcham.jpg',
//                     'https://s3.holitech.cloud/travelqar/images/thuydienialy.jpg',
//                   ],
//                   server: "https://s3.holitech.cloud/travelqar/mp4/",
//                   onImageDetected: (imageName) =>
//                       _onImageDetected(context, imageName),
//                 ),
//               ],
//             );
//           },
//         ),
//       ),
//     );
//   }
// }

import 'dart:io';

import 'package:ar_images_holi/ar_quido.dart';
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
  String? _recognizedImage;

  List<String> cachedImagePaths = [];

  final List<String> imageUrls = [
    'https://s3.holitech.cloud/travelqar/images/baotang.jpg',
    'https://s3.holitech.cloud/travelqar/images/flcsafari.jpg',
    'https://s3.holitech.cloud/travelqar/images/hohoankiem.jpg',
    'https://s3.holitech.cloud/travelqar/images/khamphakhoahoc.jpg',
    'https://s3.holitech.cloud/travelqar/images/thapcham.jpg',
    'https://s3.holitech.cloud/travelqar/images/thuydienialy.jpg',
    'https://s3.holitech.cloud/travelqar/images/eogio.jpg',
  ];

  @override
  void initState() {
    super.initState();

    downloadAndCacheImages();
  }

  Future<void> downloadAndCacheImages() async {
    final directory = await getApplicationDocumentsDirectory();

    print('CACHE DIRECTORY: ${directory.path}');

    List<String> paths = [];

    for (final url in imageUrls) {
      try {
        final fileName = url.split('/').last;

        final filePath = '${directory.path}/$fileName';

        final file = File(filePath);

        if (await file.exists()) {
          print('CACHE EXISTS: $filePath');
        } else {
          print('DOWNLOADING: $url');

          await Dio().download(
            url,
            filePath,
          );

          print('DOWNLOADED SUCCESS: $filePath');
        }

        final savedFile = File(filePath);

        print('FILE EXISTS: ${await savedFile.exists()}');

        print('FILE SIZE: ${await savedFile.length()} bytes');

        paths.add(filePath);
      } catch (e) {
        print('DOWNLOAD ERROR: $e');
      }
    }

    print('TOTAL CACHED IMAGES: ${paths.length}');

    for (final path in paths) {
      print('LOCAL PATH: $path');
    }

    setState(() {
      cachedImagePaths = paths;
    });
  }

  void _onImageDetected(
    BuildContext context,
    String? imageName,
  ) {
    if (imageName != null && _recognizedImage != imageName) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Recognized image: $imageName',
          ),
          duration: const Duration(
            milliseconds: 2500,
          ),
        ),
      );
    }

    setState(() {
      _recognizedImage = imageName;
    });
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
                        /// truyền local file path
                        referenceImageNames: const [
                          'baotang.jpg',
                          'flcsafari.jpg',
                          'hohoankiem.jpg',
                          'khamphakhoahoc.jpg',
                          'thapcham.jpg',
                          'thuydienialy.jpg',
                          'eogio.jpg',
                        ],
                        referenceImageUrl: cachedImagePaths,

                        /// truyền local file path
                        server: "https://s3.holitech.cloud/travelqar/mp4/",
                        onImageDetected: (imageName) =>
                            _onImageDetected(context, imageName),
                      ),
                    ],
                  );
                },
              ),
      ),
    );
  }
}
