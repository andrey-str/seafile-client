//
// Created by Andrey Streltsov on 18/05/15.
//

#ifndef SEAFILE_CLIENT_NEWRENDERTAB_H
#define SEAFILE_CLIENT_NEWRENDERTAB_H


#include <qwebview.h>
#include "tab-view.h"

class NewRenderTab : public TabView {

    Q_OBJECT

public:
    explicit NewRenderTab(QWidget *parent=0);
public:

    void refresh();
    void startRefresh();
    void stopRefresh();

    void createWebKitView();
private:
    QWidget* _webViewWidget;
    QWebView* _webView;
};


#endif //SEAFILE_CLIENT_NewRenderTab_H
