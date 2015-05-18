//
// Created by Andrey Streltsov on 18/05/15.
//

#include <QtGlobal>

#if (QT_VERSION >= QT_VERSION_CHECK(5, 0, 0))
#include <QtWidgets>
#else
#include <QtGui>
#endif

#include <QtWidgets/qboxlayout.h>
#include <QtWebKit/QtWebKit>
#include "renders-tab.h"

enum {
    INDEX_WEB_VIEW = 0,
};


RendersTab::RendersTab(QWidget *parent): TabView(parent) {

    createWebKitView();

    QUrl url = QUrl("http://www.yandex.ru");
    _webView->load(url);

    mStack->insertWidget(INDEX_WEB_VIEW, _webViewWidget);

}

void RendersTab::createWebKitView() {

    _webViewWidget = new QWidget(this);
    _webViewWidget->setObjectName("RenderTabWebKitViewWidget");

    QVBoxLayout *layout = new QVBoxLayout;
    _webViewWidget->setLayout(layout);


    _webView = new QWebView(_webViewWidget);
    layout->addWidget(_webView);
}

void RendersTab::startRefresh() {

}

void RendersTab::refresh() {

    _webView->reload();
}

void RendersTab::stopRefresh() {

}
