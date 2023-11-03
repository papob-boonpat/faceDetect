//
//  ViewController.swift
//  faceReg
//
//  Created by papob boonpat on 25/10/2566 BE.
//

import UIKit
import Vision
import AVFoundation

class ViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate  {
  
  
  private let captureSession = AVCaptureSession()
  private lazy var previewLayer = AVCaptureVideoPreviewLayer(session: self.captureSession)
  private let videoDataOutput = AVCaptureVideoDataOutput()
  private var drawings: [CAShapeLayer] = []
  
  @IBOutlet weak var previewView: UIView!
  @IBOutlet weak var turnLeft: UILabel!
  @IBOutlet weak var turnRight: UILabel!
  @IBOutlet weak var eyeClose: UILabel!
  override func viewDidLoad() {
    super.viewDidLoad()
    self.addCameraInput()
    self.showCameraFeed()
    self.getCameraFrames()
    self.captureSession.startRunning()
  }
  
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    self.previewLayer.frame = self.previewView.frame
  }
  
  func captureOutput(
    _ output: AVCaptureOutput,
    didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection) {
      
      guard let frame = CMSampleBufferGetImageBuffer(sampleBuffer) else {
        debugPrint("unable to get image from sample buffer")
        return
      }
      self.detectFace(in: frame)
    }
  
  private func addCameraInput() {
    guard let device = AVCaptureDevice.DiscoverySession(
      deviceTypes: [.builtInWideAngleCamera, .builtInDualCamera, .builtInTrueDepthCamera],
      mediaType: .video,
      position: .front).devices.first else {
      fatalError("No back camera device found, please make sure to run SimpleLaneDetection in an iOS device and not a simulator")
    }
    let cameraInput = try! AVCaptureDeviceInput(device: device)
    self.captureSession.addInput(cameraInput)
  }
  
  private func showCameraFeed() {
    self.previewLayer.videoGravity = .resizeAspectFill
    self.previewView.layer.addSublayer(self.previewLayer)
    self.previewLayer.frame = self.previewView.frame
  }
  
  private func getCameraFrames() {
    self.videoDataOutput.videoSettings = [(kCVPixelBufferPixelFormatTypeKey as NSString) : NSNumber(value: kCVPixelFormatType_32BGRA)] as [String : Any]
    self.videoDataOutput.alwaysDiscardsLateVideoFrames = true
    self.videoDataOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "camera_frame_processing_queue"))
    self.captureSession.addOutput(self.videoDataOutput)
    guard let connection = self.videoDataOutput.connection(with: AVMediaType.video),
          connection.isVideoRotationAngleSupported(90) else { return }
    if #available(iOS 17.0, *) {
      connection.videoRotationAngle = 90
    } else {
      connection.videoOrientation = .portrait
    }
  }
  
  private func detectFace(in image: CVPixelBuffer) {
    let faceDetectionRequest = VNDetectFaceLandmarksRequest(completionHandler: { (request: VNRequest, error: Error?) in
      DispatchQueue.main.async {
        if let results = request.results as? [VNFaceObservation] {
          self.handleFaceDetectionResults(results)
        } else {
          self.clearDrawings()
        }
      }
    })
    let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: image, orientation: .leftMirrored, options: [:])
    try? imageRequestHandler.perform([faceDetectionRequest])
  }
  
  private func handleFaceDetectionResults(_ observedFaces: [VNFaceObservation]) {
    
    self.clearDrawings()
    let facesBoundingBoxes: [CAShapeLayer] = observedFaces.flatMap({ (observedFace: VNFaceObservation) -> [CAShapeLayer] in
      if Float(truncating: observedFace.yaw ?? 0)  > 0 {
        turnRight.isHidden = false
      }
      if Float(truncating: observedFace.yaw ?? 0)  < 0 {
        turnLeft.isHidden = false
      }
      let faceBoundingBoxOnScreen = self.previewLayer.layerRectConverted(fromMetadataOutputRect: observedFace.boundingBox)
      let faceBoundingBoxPath = CGPath(rect: faceBoundingBoxOnScreen, transform: nil)
      let faceBoundingBoxShape = CAShapeLayer()
      faceBoundingBoxShape.path = faceBoundingBoxPath
      faceBoundingBoxShape.fillColor = UIColor.clear.cgColor
      faceBoundingBoxShape.strokeColor = UIColor.red.cgColor
      var newDrawings = [CAShapeLayer]()
      newDrawings.append(faceBoundingBoxShape)
      if let landmarks = observedFace.landmarks {
        newDrawings = newDrawings + self.drawFaceFeatures(landmarks, screenBoundingBox: faceBoundingBoxOnScreen)
      }
      return newDrawings
    })
    facesBoundingBoxes.forEach({ faceBoundingBox in self.previewView.layer.addSublayer(faceBoundingBox) })
    self.drawings = facesBoundingBoxes
  }
  
  private func clearDrawings() {
    self.drawings.forEach({ drawing in drawing.removeFromSuperlayer() })
  }
  
  private func drawFaceFeatures(_ landmarks: VNFaceLandmarks2D, screenBoundingBox: CGRect) -> [CAShapeLayer] {
    var faceFeaturesDrawings: [CAShapeLayer] = []
    if let leftEye = landmarks.leftEye {
      let eyeDrawing = self.drawEye(leftEye, screenBoundingBox: screenBoundingBox)
      faceFeaturesDrawings.append(eyeDrawing)
    }
    if let rightEye = landmarks.rightEye {
      let eyeDrawing = self.drawEye(rightEye, screenBoundingBox: screenBoundingBox)
      faceFeaturesDrawings.append(eyeDrawing)
    }
    // draw other face features here
    return faceFeaturesDrawings
  }
  private func drawEye(_ eye: VNFaceLandmarkRegion2D, screenBoundingBox: CGRect) -> CAShapeLayer {
    let eyePath = CGMutablePath()
    let eyePathPoints = eye.normalizedPoints
      .map({ eyePoint in
        CGPoint(
          x: eyePoint.y * screenBoundingBox.height + screenBoundingBox.origin.x,
          y: eyePoint.x * screenBoundingBox.width + screenBoundingBox.origin.y)
      })
    let isEyeClose = (abs(eyePathPoints[1].y - eyePathPoints[5].y) + abs(eyePathPoints[3].y - eyePathPoints[4].y))/(2 * abs(eyePathPoints[0].x - eyePathPoints[3].x))
    if isEyeClose < 0.1 {
      eyeClose.isHidden = false
    }
    eyePath.addLines(between: eyePathPoints)
    eyePath.closeSubpath()
    let eyeDrawing = CAShapeLayer()
    eyeDrawing.path = eyePath
    eyeDrawing.fillColor = UIColor.clear.cgColor
    eyeDrawing.strokeColor = UIColor.red.cgColor
    return eyeDrawing
  }
  
}
