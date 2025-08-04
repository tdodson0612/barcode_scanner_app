import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'barcode_utils.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  File? _imageFile;
  String _message = "";
  bool _isLoading = false;

  Future<void> _takePhoto() async {
    setState(() {
      _message = "";
      _imageFile = null;
    });

    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.camera);

    if (pickedFile != null) {
      setState(() {
        _imageFile = File(pickedFile.path);
      });
    } else {
      setState(() {
        _message = "No photo taken.";
      });
    }
  }

  Future<void> _submitPhoto() async {
    if (_imageFile == null) {
      setState(() {
        _message = "No image to submit.";
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _message = "Decoding barcode...";
    });

    final result = await decodeBarcodeAndLookup(_imageFile!.path);

    setState(() {
      _isLoading = false;
      _message = result;
    });
  }

  void _retakePhoto() {
    setState(() {
      _imageFile = null;
      _message = "";
    });
    _takePhoto();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Barcode Scanner'),
      ),
      body: Center(
        child: _isLoading
            ? const CircularProgressIndicator()
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_imageFile != null)
                    Image.file(
                      _imageFile!,
                      width: 200,
                      height: 200,
                    ),
                  const SizedBox(height: 20),
                  Text(
                    _message,
                    style: const TextStyle(fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  if (_imageFile == null)
                    ElevatedButton(
                      onPressed: _takePhoto,
                      child: const Text('Take Photo'),
                    )
                  else ...[
                    ElevatedButton(
                      onPressed: _submitPhoto,
                      child: const Text('Submit Photo'),
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton(
                      onPressed: _retakePhoto,
                      child: const Text('Retake Photo'),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}
