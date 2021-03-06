import 'dart:io' as io;

import 'package:camera/camera.dart';
import 'package:firebase_ml_vision/firebase_ml_vision.dart';
import 'package:flutter/material.dart';

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:tflite/tflite.dart';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key key, this.title}) : super(key: key);

  final String title;

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  io.File imageFile;
  FirebaseVisionImage visionImage;
  FaceDetector faceDetector;

  CameraController controller;
  List cameras;
  int selectedCameraIdx;
  String imagePath;

  bool started = false;

  int statusLight = 0;

  //Load the Tflite model
  loadModel() async {
    await Tflite.loadModel(
      model: "assets/model_unquant.tflite",
      labels: "assets/labels.txt",
    );
  }

  Future<String> sendData() async {
    http.Response response = await http.get(
      Uri.encodeFull("https://ps.pndsn.com/publish/pub-c-b3c97c3a-4572-44ac-91d4-942e9dcecc86/sub-c-052a7e96-86f4-11e9-9f15-ba4fa582ffed/0/flutter_iot_lamp/0/{\"action\":$statusLight}?uuid=db9c5e39-7c95-40f5-8d71-125765b6f561"),
    );

    print(response.body);
  }

  @override
  void initState() {
    super.initState();

    loadModel();

    availableCameras().then((availableCameras) {

      cameras = availableCameras;
      if (cameras.length > 0) {
        setState(() {
          selectedCameraIdx = 0;
        });

        _initCameraController(cameras[selectedCameraIdx]).then((void v) {});
      }else{
        print("No camera available");
      }
    }).catchError((err) {
      print('Error: $err.code\nError Message: $err.message');
    });
  }

  Future _initCameraController(CameraDescription cameraDescription) async {
    if (controller != null) {
      await controller.dispose();
    }

    controller = CameraController(cameraDescription, ResolutionPreset.high);

    controller.addListener(() {
      if (mounted) {
        setState(() {});
      }

      if (controller.value.hasError) {
        print('Camera error ${controller.value.errorDescription}');
      }
    });

    try {
      await controller.initialize();
    } on CameraException catch (e) {
      print(e);
    }

    if (mounted) {
      setState(() {});
    }
  }

  // Classifiy the image selected
  classifyImage(io.File image) async {
    var output = await Tflite.runModelOnImage(
      path: image.path,
      numResults: 2,
      threshold: 0.2,
      imageMean: 127.5,
      imageStd: 127.5,
    );

    print('sucess');
  }

  void _faceDetector(io.File imageFile) async{
    //1 - cria uma instância de FirebaseVisionImage a partir de um arquivo (instância de File)
    visionImage = FirebaseVisionImage.fromFile(imageFile);

    //2 - se o FaceDetecetor (variável criada na classe) ainda não foi instanciada, será instanciada
    //3 - passamos um FaceDetectorOptions como parâmetro para detalhar quais features queremos no detector de faces. Por exemplo, pra saber a probabilidade da pessoa estar rindo ou não, o enableClassification deve estar marcado como true.
    if (faceDetector == null) {
      faceDetector = FirebaseVision.instance.faceDetector(FaceDetectorOptions(
          enableClassification: true,
          enableTracking: true,
          enableLandmarks: true,
          enableContours: true
      ));
    }

    //4 - o detector de faces processa a imagem e retorna uma lista com as faces encontradas. A lista pode ter 0 (zero) elementos.
    final List<Face> faces = await faceDetector.processImage(visionImage);

    //5 - um laço for nas faces é feito
    for (Face face in faces) {

      //6 - verificamos se o smilingProbability está diferente de nulo. Seu valor vai de 0.0 (0% de probabilidade de riso) até 1.0 (100% de probabilidade de riso)
      if (face.smilingProbability != null) {
        final double smileProb = face.smilingProbability;

        //7 - mudamos o valor do statusLight e depois enviamos isso para um Arduino Uno, que vai ligar ou desligar a lâmpada de balada
        if (statusLight == 0){
          if (smileProb > 0.85) {
            statusLight = 1;
            sendData();
          }
        } else {
          if (smileProb < 0.85) {
            statusLight = 0;
            sendData();
          }
        }
      }

    }

    //8 - depois de um tempo muito curto, capturamos outra foto e o processo é reiniciado
    Future.delayed(Duration(seconds: 1), (){
      _capture();
    });
  }

  @override
  void dispose() {
    super.dispose();
    faceDetector.close();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Firebase + Machine Learning'),
        backgroundColor: Colors.blueGrey,
      ),
      body: Container(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(
                flex: 1,
                child: _cameraPreviewWidget(),
              ),
              //(2) mostrar uma widget ou outra
              started ? Container() :
              Column(
                children: <Widget>[
                  SizedBox(height: 10.0),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      _cameraTogglesRowWidget(),
                      _captureControlRowWidget(context),
                      Spacer()
                    ],
                  ),
                  SizedBox(height: 20.0)
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cameraPreviewWidget() {
    if (controller == null || !controller.value.isInitialized) {
      return const Text(
        'Loading',
        style: TextStyle(
          color: Colors.white,
          fontSize: 20.0,
          fontWeight: FontWeight.w900,
        ),
      );
    }

    return AspectRatio(
      aspectRatio: controller.value.aspectRatio,
      child: CameraPreview(controller),
    );
  }

  Widget _captureControlRowWidget(context) {
    return Expanded(
      child: Align(
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          mainAxisSize: MainAxisSize.max,
          children: [
            FloatingActionButton(
                child: Icon(Icons.camera),
                backgroundColor: Colors.blueGrey,
                onPressed: () {
                  setState(() {
                    started = true;
                  });

                  //(1) vai começar a captura
                  _capture();
                })
          ],
        ),
      ),
    );
  }

  Widget _cameraTogglesRowWidget() {
    if (cameras == null || cameras.isEmpty) {
      return Spacer();
    }

    CameraDescription selectedCamera = cameras[selectedCameraIdx];
    CameraLensDirection lensDirection = selectedCamera.lensDirection;

    return Expanded(
      child: Align(
        alignment: Alignment.centerLeft,
        child: FlatButton.icon(
            onPressed: _onSwitchCamera,
            icon: Icon(_getCameraLensIcon(lensDirection)),
            label: Text(
                "${lensDirection.toString().substring(lensDirection.toString().indexOf('.') + 1)}")),
      ),
    );
  }

  void _onSwitchCamera() {
    selectedCameraIdx =
    selectedCameraIdx < cameras.length - 1 ? selectedCameraIdx + 1 : 0;
    CameraDescription selectedCamera = cameras[selectedCameraIdx];
    _initCameraController(selectedCamera);
  }

  IconData _getCameraLensIcon(CameraLensDirection direction) {
    switch (direction) {
      case CameraLensDirection.back:
        return Icons.camera_rear;
      case CameraLensDirection.front:
        return Icons.camera_front;
      case CameraLensDirection.external:
        return Icons.camera;
      default:
        return Icons.device_unknown;
    }
  }

  void _capture() async {
    try {
      final path = join(
        (await getTemporaryDirectory()).path,
        '${DateTime.now()}.png',
      );

      await controller.takePicture(path);

      io.File file = io.File(path);
      _faceDetector(file);
    } catch (e) {
      print(e);
    }
  }

}
