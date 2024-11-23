import SwiftUI
import AVFoundation

// ContentView with DrawingView
struct ContentView: View {
    @State private var predictedShape = "Draw a shape..."
    @State private var isTraining = false
    @State private var isPredicting = false
    @State private var selectedShape: String? = nil
    @StateObject private var viewModel = DrawingViewModel()
    
    var body: some View {
        VStack {
            // Drawing Canvas
            DrawingView(viewModel: viewModel)
                .frame(height: 300)
                .border(Color.black)
            
            // Training Section
            VStack(spacing: 20) {
                Text("Training")
                    .font(.headline)
                
                HStack(spacing: 20) {
                    ForEach(["Circle", "Square", "Triangle", "Line"], id: \.self) { shape in
                        Button(shape) {
                            if selectedShape == shape {
                                selectedShape = nil
                                predictedShape = "Draw a shape..."
                            } else {
                                selectedShape = shape
                                predictedShape = "Selected: \(shape)\nDraw and Submit"
                            }
                        }
                        .buttonStyle(.bordered)
                        .background(selectedShape == shape ? Color.blue.opacity(0.3) : Color.clear)
                        .disabled(isTraining || isPredicting)
                    }
                }
                
                if selectedShape != nil {
                    Button("Submit Training") {
                        if let shape = selectedShape {
                            trainShape(as: shape)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isTraining || isPredicting)
                }
                
                Divider()
                    .padding(.vertical)
                
                // Action Buttons
                HStack(spacing: 30) {
                    Button("Clear") {
                        NotificationCenter.default.post(name: NSNotification.Name("ClearDrawing"), object: nil)
                        predictedShape = "Draw a shape..."
                        selectedShape = nil
                    }
                    .buttonStyle(.bordered)
                    .disabled(isTraining || isPredicting)
                    
                    Button("Predict") {
                        predictCurrentShape()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isTraining || isPredicting || selectedShape != nil)
                }
                
                // Status Text
                Text(predictedShape)
                    .font(.headline)
                    .padding()
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
    }
    
    private func trainShape(as shape: String) {
        guard let drawingView = viewModel.drawingView,
              let image = drawingView.getDrawingImage() else {
            predictedShape = "Error getting drawing"
            return
        }
        
        isTraining = true
        predictedShape = "Training as \(shape)..."
        
        Task {
            do {
                let message = try await NetworkManager.shared.trainShape(image: image, label: shape)
                await MainActor.run {
                    NotificationCenter.default.post(name: NSNotification.Name("ClearDrawing"), object: nil)
                    selectedShape = nil
                    predictedShape = message
                    isTraining = false
                }
            } catch {
                await MainActor.run {
                    predictedShape = "Error training: \(error.localizedDescription)"
                    isTraining = false
                }
            }
        }
    }
    
    private func predictCurrentShape() {
        guard let drawingView = viewModel.drawingView,
              let image = drawingView.getDrawingImage() else {
            predictedShape = "Error getting drawing"
            return
        }
        
        isPredicting = true
        predictedShape = "Predicting..."
        
        Task {
            do {
                let prediction = try await NetworkManager.shared.predictShape(image: image)
                await MainActor.run {
                    predictedShape = prediction
                    isPredicting = false
                }
            } catch {
                await MainActor.run {
                    predictedShape = "Error predicting: \(error.localizedDescription)"
                    isPredicting = false
                }
            }
        }
    }
}

// DrawingView SwiftUI wrapper
struct DrawingView: UIViewRepresentable {
    let viewModel: DrawingViewModel
    
    func makeUIView(context: Context) -> UIDrawingView {
        let view = UIDrawingView()
        viewModel.drawingView = view
        return view
    }
    
    func updateUIView(_ uiView: UIDrawingView, context: Context) {
    }
}

// UIDrawingView implementation
class UIDrawingView: UIView {
    private var lines: [[CGPoint]] = []
    private var currentLine: [CGPoint] = []
    private var drawingBounds: CGRect = .zero
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .white
        
        NotificationCenter.default.addObserver(self,
                                             selector: #selector(clearDrawing),
                                             name: NSNotification.Name("ClearDrawing"),
                                             object: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let point = touches.first?.location(in: self) else { return }
        currentLine = [point]
        updateDrawingBounds(with: point)
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let point = touches.first?.location(in: self) else { return }
        currentLine.append(point)
        updateDrawingBounds(with: point)
        setNeedsDisplay()
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let point = touches.first?.location(in: self) else { return }
        currentLine.append(point)
        lines.append(currentLine)
        updateDrawingBounds(with: point)
        setNeedsDisplay()
        currentLine = []
    }
    
    private func updateDrawingBounds(with point: CGPoint) {
        if drawingBounds.isNull {
            drawingBounds = CGRect(origin: point, size: .zero)
        } else {
            drawingBounds = drawingBounds.union(CGRect(origin: point, size: .zero))
        }
    }
    
    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        
        context.setStrokeColor(UIColor.black.cgColor)
        context.setLineWidth(3)
        context.setLineCap(.round)
        
        // Draw completed lines
        lines.forEach { line in
            guard let firstPoint = line.first else { return }
            
            context.beginPath()
            context.move(to: firstPoint)
            line.dropFirst().forEach { point in
                context.addLine(to: point)
            }
            context.strokePath()
        }
        
        // Draw current line
        if let firstPoint = currentLine.first {
            context.beginPath()
            context.move(to: firstPoint)
            currentLine.dropFirst().forEach { point in
                context.addLine(to: point)
            }
            context.strokePath()
        }
    }
    
    @objc func clearDrawing() {
        lines = []
        currentLine = []
        drawingBounds = .zero
        setNeedsDisplay()
    }
    
    func getDrawingImage() -> UIImage? {
        // Ensure we have a valid drawing
        guard !lines.isEmpty || !currentLine.isEmpty else { return nil }
        
        // Add padding to the drawing bounds
        let padding: CGFloat = 20
        var bounds = drawingBounds.insetBy(dx: -padding, dy: -padding)
        
        // Ensure minimum size and handle empty bounds
        let minSize: CGFloat = 100
        if bounds.width < minSize || bounds.height < minSize {
            let center = CGPoint(x: self.bounds.midX, y: self.bounds.midY)
            bounds = CGRect(x: center.x - minSize/2,
                          y: center.y - minSize/2,
                          width: minSize,
                          height: minSize)
        }
        
        // Create the image context
        UIGraphicsBeginImageContextWithOptions(bounds.size, true, 0.0)
        defer { UIGraphicsEndImageContext() }
        
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        
        // Fill background
        UIColor.white.setFill()
        context.fill(CGRect(origin: .zero, size: bounds.size))
        
        // Setup drawing parameters
        context.setStrokeColor(UIColor.black.cgColor)
        context.setLineWidth(3)
        context.setLineCap(.round)
        
        // Translate context to draw relative to bounds
        context.translateBy(x: -bounds.minX, y: -bounds.minY)
        
        // Draw all lines
        lines.forEach { line in
            guard let firstPoint = line.first else { return }
            context.beginPath()
            context.move(to: firstPoint)
            line.dropFirst().forEach { context.addLine(to: $0) }
            context.strokePath()
        }
        
        return UIGraphicsGetImageFromCurrentImageContext()
    }
}
