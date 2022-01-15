#include <opencv2/core.hpp>
#include <opencv2/imgproc.hpp>
#include <opencv2/imgcodecs.hpp>
#include "ArucoDetector.h"
#include <iostream>

using namespace std;
using namespace cv;

static ArucoDetector* detector = nullptr;

void rotateMat(Mat &matImage, int rotation)
{
	if (rotation == 90) {
		transpose(matImage, matImage);
		flip(matImage, matImage, 1); //transpose+flip(1)=CW
	} else if (rotation == 270) {
		transpose(matImage, matImage);
		flip(matImage, matImage, 0); //transpose+flip(0)=CCW
	} else if (rotation == 180) {
		flip(matImage, matImage, -1);    //flip(-1)=180
	}
}

extern "C" {
	// Attributes to prevent 'unused' function from being removed and to make it visible
	__attribute__((visibility("default"))) __attribute__((used))
	const char* version() {
		return CV_VERSION;
	}

	__attribute__((visibility("default"))) __attribute__((used))
	void initDetector(uint8_t* markerPngBytes, int inBytesCount, int bits) {
		if (detector != nullptr) {
			delete detector;
			detector = nullptr;
		}

		vector<uint8_t> buffer(markerPngBytes, markerPngBytes + inBytesCount);
		Mat marker = imdecode(buffer, IMREAD_COLOR);

		detector = new ArucoDetector(marker, bits);
	}

	__attribute__((visibility("default"))) __attribute__((used))
	void destroyDetector() {
		if (detector != nullptr) {
			delete detector;
			detector = nullptr;
		}
	}

	__attribute__((visibility("default"))) __attribute__((used))
	const float* detect(int width, int height, int rotation, uint8_t* bytes, bool isYUV, int32_t* outCount) {
		if (detector == nullptr) {
			float* jres = new float[1];
			jres[0] = 0;
			return jres;
		}

		Mat frame;
		if (isYUV) {
			Mat myyuv(height + height / 2, width, CV_8UC1, bytes);
			cvtColor(myyuv, frame, COLOR_YUV2BGRA_NV21);
		} else {
			frame = Mat(height, width, CV_8UC4, bytes);
		}

		rotateMat(frame, rotation);
		cvtColor(frame, frame, COLOR_BGRA2GRAY);
		vector<ArucoResult> res = detector->detectArucos(frame, 0);

		vector<float> output;

		for (int i = 0; i < res.size(); ++i) {
			ArucoResult ar = res[i];
			// each aruco has 4 corners
			output.push_back(ar.corners[0].x);
			output.push_back(ar.corners[0].y);
			output.push_back(ar.corners[1].x);
			output.push_back(ar.corners[1].y);
			output.push_back(ar.corners[2].x);
			output.push_back(ar.corners[2].y);
			output.push_back(ar.corners[3].x);
			output.push_back(ar.corners[3].y);
		}

		// Copy result bytes as output vec will get freed
		unsigned int total = sizeof(float) * output.size();
		float* jres = (float*)malloc(total);
		memcpy(jres, output.data(), total);

		*outCount = output.size();
		return jres;
	}
}