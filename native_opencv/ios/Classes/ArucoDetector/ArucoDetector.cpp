#include <opencv2/imgproc.hpp>
#include "ArucoDetector.h"

using namespace std;
using namespace cv;

ArucoDetector::ArucoDetector(Mat marker, int bits) {
	m_dict = loadMarkerDictionary(marker, bits);
}

vector<int> ArucoDetector::getContoursBits(Mat image, vector<Point2f> cnt, int bits) {
	assert(bits > 0 && round(sqrt(bits)) == sqrt(bits));
	int pixelLen = sqrt(bits);

	// NOTE: we assume contour points are clockwise starting from top-left
	vector<Point2f> corners = { Point2f(0, 0), Point2f(bits, 0), Point2f(bits, bits), Point2f(0, bits) };
	Mat M = getPerspectiveTransform(cnt, corners);
	Mat warpped;
	warpPerspective(image, warpped, M, Size(bits, bits));

	Mat binary;
	threshold(warpped, binary, 0, 255, THRESH_BINARY | THRESH_OTSU);

	Mat element = getStructuringElement(MORPH_RECT, Size(3, 3));
	erode(binary, binary, element);

	vector<int> res;
	for (int r = 0; r < pixelLen; ++r) {
		for (int c = 0; c < pixelLen; ++c) {
			int y = r * pixelLen + (pixelLen / 2);
			int x = c * pixelLen + (pixelLen / 2);
			if (binary.at<uchar>(y, x) >= 128)
			{
				res.push_back(1);
			}
			else
			{
				res.push_back(0);
			}
		}
	}

	return res;
}

bool ArucoDetector::equalSig(vector<int>& sig1, vector<int>& sig2, int allowedMisses)
{
	int misses = 0;
	for (int i = 0; i < sig1.size(); ++i) {
		if (sig1[i] != sig2[i])
			++misses;
	}

	return misses <= allowedMisses;
}

void ArucoDetector::orderContour(vector<Point2f>& cnt)
{
	float cx = (cnt[0].x + cnt[1].x + cnt[2].x + cnt[3].x) / 4.0f;
	float cy = (cnt[0].y + cnt[1].y + cnt[2].y + cnt[3].y) / 4.0f;

	// IMPORTANT! We assume the contour points are counter-clockwise (as we use EXTERNAL contours in findContours)
	if (cnt[0].x <= cx && cnt[0].y <= cy)
	{
		swap(cnt[1], cnt[3]);
	}
	else
	{
		swap(cnt[0], cnt[1]);
		swap(cnt[2], cnt[3]);
	}
}

vector<vector<Point2f>> ArucoDetector::findSquares(Mat img) {
	vector<vector<Point2f>> cand;

	Mat thresh;
	adaptiveThreshold(img, thresh, 255, ADAPTIVE_THRESH_MEAN_C, THRESH_BINARY, 11, 5);

	thresh = ~thresh;
	vector<vector<Point>> cnts;
	findContours(thresh, cnts, RETR_EXTERNAL, CHAIN_APPROX_SIMPLE);

	vector<Point2f> cnt;
	for (int i = 0; i < cnts.size(); ++i)
	{
		approxPolyDP(cnts[i], cnt, 0.05 * arcLength(cnts[i], true), true);
		if (cnt.size() != 4 || contourArea(cnt) < 200 || !isContourConvex(cnt)) {
			continue;
		}

		cornerSubPix(img, cnt, Size(5, 5), Size(-1, -1), TERM_CRIT);

		orderContour(cnt);
		cand.push_back(cnt);
	}

	return cand;
}

vector<ArucoResult> ArucoDetector::detectArucos(Mat frame, int misses) {
	vector<ArucoResult> res;
	vector<vector<Point2f>> cands = findSquares(frame);

	for (int i = 0; i < cands.size() && res.size() < 3; ++i) {
		vector<Point2f> cnt = cands[i];
		vector<int> sig = getContoursBits(frame, cnt, 36);
		for (int j = 0; j < m_dict.sigs.size(); ++j) {
			if (equalSig(sig, m_dict.sigs[j], misses)) {
				ArucoResult ar;
				ar.corners = cnt;
				ar.index = j;
				res.push_back(ar);
				break;
			}
		}
	}

	return res;
}

ArucoDict ArucoDetector::loadMarkerDictionary(Mat marker, int bits) {
	ArucoDict res;
	int w = marker.cols;
	int h = marker.rows;

	cvtColor(marker, marker, COLOR_BGRA2GRAY);

	vector<Point2f> cnt = { Point2f(0, 0), Point2f(w, 0) , Point2f(w, h) , Point2f(0, h) };
	vector<Point3f> world = { Point3f(0, 0, 0), Point3f(25, 0, 0), Point3f(25, 25, 0), Point3f(0, 25, 0) };

	for (int i = 0; i < 4; ++i) {
		vector<int> sig = getContoursBits(marker, cnt, bits);
		res.sigs.push_back(sig);

		vector<Point3f> w(world);
		res.worldLoc.push_back(w);

		rotate(marker, marker, ROTATE_90_CLOCKWISE);

		world.insert(world.begin(), world[3]);
		world.pop_back();
	}

	return res;
}
