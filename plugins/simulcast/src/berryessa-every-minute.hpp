
#pragma once

#include <QObject>
#include <QDateTime>
#include <QTimer>

#include "presentmon-csv-capture.hpp"

#include <util/platform.h>

#include <memory>

class BerryessaSubmitter;

struct OSCPUUsageInfoDeleter {
	void operator()(os_cpu_usage_info *info)
	{
		os_cpu_usage_info_destroy(info);
	}
};

struct OBSFrameCounters {
	uint32_t output, skipped;
	uint32_t rendered, lagged;
};

class BerryessaEveryMinute : public QObject {
	Q_OBJECT
public:
	BerryessaEveryMinute(QObject *parent, BerryessaSubmitter *berryessa);
	virtual ~BerryessaEveryMinute();

private slots:
	void fire();

private:
	BerryessaSubmitter *berryessa_;
	PresentMonCapture presentmon_;
	QTimer timer_;
	QDateTime startTime_;

	std::unique_ptr<os_cpu_usage_info, OSCPUUsageInfoDeleter>
		obs_cpu_usage_info_;

	OBSFrameCounters frame_counters_;
};
