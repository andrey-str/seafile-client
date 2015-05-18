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
#include "new-render-tab.h"

enum {
    INDEX_WEB_VIEW = 0,
};


NewRenderTab::NewRenderTab(QWidget *parent): TabView(parent) {

    createWebKitView();

    QUrl url = QUrl("http://www.rambler.ru");
    _webView->load(url);

    mStack->insertWidget(INDEX_WEB_VIEW, _webViewWidget);

}

void NewRenderTab::createWebKitView() {

    _webViewWidget = new QWidget(this);
    _webViewWidget->setObjectName("RenderTabWebKitViewWidget");

    QVBoxLayout *layout = new QVBoxLayout;
    _webViewWidget->setLayout(layout);


    _webView = new QWebView(_webViewWidget);
    layout->addWidget(_webView);
}

void NewRenderTab::startRefresh() {

}

void NewRenderTab::refresh() {

    _webView->reload();
}

void NewRenderTab::stopRefresh() {

}
